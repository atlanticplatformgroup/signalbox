import { parse, deparse } from "pgsql-parser";
import type { Pool } from "pg";
import { GovernanceBundleCompiler } from "./bundle-compiler.mjs";
import { ArchitectureRepository, GovernanceAdministrationError, verifyGovernanceBundleArtifacts } from "./repository.mjs";
import type { ObjectArtifactStore } from "./object-store.mjs";

export interface PolicyInstaller {
  install(orgId: string, bundleId: string, principalId: string): Promise<void>;
}

/** DDL credentials stay in the trusted host, never in the gateway or agent token. */
export class PostgresPolicyInstaller implements PolicyInstaller {
  constructor(
    private readonly pool: Pool,
    private readonly repository: ArchitectureRepository,
    private readonly objects: ObjectArtifactStore,
    private readonly compiler: GovernanceBundleCompiler,
  ) {}

  async install(orgId: string, bundleId: string, principalId: string): Promise<void> {
    if (!await this.repository.canAdministerGovernance(orgId, principalId)) throw new GovernanceAdministrationError();
    const record = await this.repository.governanceBundle(orgId, bundleId);
    if (!record) throw new Error("Policy bundle does not exist in this organization");
    const bundle = await verifyGovernanceBundleArtifacts(record, this.objects);
    const source = new TextDecoder().decode(await this.objects.get(record.sourceObjectKey));
    // Never execute SQL supplied by a client or merely trusted because it has a hash.
    const { bundle: rebuilt } = await this.compiler.validate(orgId, source);
    if (rebuilt.bundleHash !== bundle.bundleHash) throw new Error("Policy artifacts do not match a fresh compilation of their source");
    const schema = `sb_policy_${bundle.bundleHash.slice(7, 55)}`;
    const sql = await relocateDecisionSql(rebuilt.enforcement.decisionSql, schema);
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL ROLE modellang_owner");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [orgId]);
      const authorized = await client.query("SELECT id FROM model_signalbox.principal WHERE id=$1 AND org_id=$2 AND kind='HUMAN' AND status='ACTIVE' AND 'ADMIN'=ANY(roles) FOR SHARE", [principalId, orgId]);
      if (!authorized.rowCount) throw new GovernanceAdministrationError();
      // Serialize shared content-addressed schemas across tenants as well.
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,1))", [schema]);
      await client.query(`CREATE SCHEMA IF NOT EXISTS "${schema}" AUTHORIZATION modellang_owner`);
      await client.query(sql);
      await client.query(`REVOKE ALL ON SCHEMA "${schema}" FROM PUBLIC, modellang_app, modellang_gateway`);
      await client.query(`REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "${schema}" FROM PUBLIC, modellang_app, modellang_gateway`);
      await client.query("INSERT INTO signalbox_architecture.installed_policy(bundle_id,org_id,schema_name) VALUES($1,$2,$3) ON CONFLICT(bundle_id) DO NOTHING", [bundleId, orgId, schema]);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}

/** Move declaration identifiers through PostgreSQL's AST; leave SQL literals and bodies intact. */
async function relocateDecisionSql(sql: string, schema: string): Promise<string> {
  if (!/^sb_policy_[a-f0-9]{48}$/.test(schema)) throw new TypeError("Invalid policy schema");
  const tree = await parse(sql);
  const names = new Set<string>();
  tree.stmts = (tree.stmts ?? []).filter(({ stmt }) => {
    if (!stmt) throw new Error("Compiler emitted an empty SQL statement");
    if ("VariableSetStmt" in stmt) {
      if (stmt.VariableSetStmt.name !== "role") throw new Error("Unexpected compiler session setting");
      return false;
    }
    // Privileges are explicitly revoked on the complete installed schema below.
    if ("GrantStmt" in stmt && !stmt.GrantStmt.is_grant) return false;
    if (!("CreateFunctionStmt" in stmt)) throw new Error("Policy SQL must contain only compiled decision functions");
    const fn = stmt.CreateFunctionStmt;
    if (fn.funcname?.length !== 2) throw new Error("Policy SQL must contain only compiled decision functions");
    const schemaNode = fn.funcname[0]!;
    const nameNode = fn.funcname[1]!;
    const originalSchema = "String" in schemaNode ? schemaNode.String.sval : undefined;
    const name = "String" in nameNode ? nameNode.String.sval : undefined;
    if (originalSchema !== "model_signalbox" || !name || !/^decide_act_[a-f0-9]+$/.test(name) || names.has(name)) {
      throw new Error("Unexpected compiler decision function identity");
    }
    names.add(name);
    fn.funcname[0] = { String: { sval: schema } };
    return true;
  });
  if (names.size === 0) throw new Error("Compiler emitted no action decisions");
  return deparse(tree);
}
