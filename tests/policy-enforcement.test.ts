// Real PostgreSQL/compiler regression suite; owns and drops only its isolated database.
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { EventEmitter, once } from "node:events";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import pg from "pg";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import { GovernanceBundleCompiler, type CompiledGovernanceBundle } from "../src/architecture/bundle-compiler.mjs";
import { MemoryArtifactStore } from "../src/architecture/object-store.mjs";
import { ArchitectureRepository } from "../src/architecture/repository.mjs";
import { PostgresPolicyInstaller } from "../src/architecture/policy-installer.mjs";
import { installPolicyGuards } from "../src/architecture/policy-guard.mjs";
import { SignalboxWorker } from "../src/worker.mjs";
import { publicDecisionExecutor } from "../src/architecture/public-decisions.mjs";
import { assembleSignalboxPublicDecisionTrace } from "../generated/signalbox/dist/http-server.js";

const ISSUER = "https://signalbox.test";
const ORG = "00000000-0000-4000-8000-0000000000a1";
const OTHER_ORG = "00000000-0000-4000-8000-0000000000a2";
const ADMIN = "00000000-0000-4000-8000-0000000000b4";
const OTHER_ADMIN = "00000000-0000-4000-8000-0000000000b5";
const REVIEWER = "00000000-0000-4000-8000-0000000000b2";
const CONNECTOR = "00000000-0000-4000-8000-0000000000c1";
const REQUEST = "action:act_ea693a4d658449fbab5741b8369bc276";
const DISPATCH = "action:act_cbb72fd307704ab3927aa4bea8112fbf";
const input = {
  delegation: "00000000-0000-4000-8000-0000000000f1",
  repository: "00000000-0000-4000-8000-0000000000d1",
  connector: CONNECTOR,
  title: "blocked-policy-input",
  body: "Private action input must not be copied to the activity feed.",
};
const otherInput = {
  ...input,
  delegation: "00000000-0000-4000-8000-0000000000f9",
  repository: "00000000-0000-4000-8000-0000000000d9",
  connector: "00000000-0000-4000-8000-0000000000c9",
};
const databaseName = `sb_policy_test_${process.pid}_${randomUUID().replaceAll("-", "").slice(0, 12)}`;
const adminUrl = new URL(process.env.SIGNALBOX_POLICY_TEST_ADMIN_URL ?? "postgresql://127.0.0.1:55433/postgres");
if (!process.env.SIGNALBOX_POLICY_TEST_ADMIN_URL) {
  // Read the local fixture credentials privately; never print Docker environment.
  const configured: unknown = JSON.parse(execFileSync("docker", ["inspect", "--format", "{{json .Config.Env}}", "sb-pg16"], { encoding: "utf8" }));
  if (!Array.isArray(configured) || configured.some((entry) => typeof entry !== "string")) throw new Error("Invalid local PostgreSQL fixture environment");
  const entries = configured as string[];
  const user = entries.find((entry) => entry.startsWith("POSTGRES_USER="))?.slice("POSTGRES_USER=".length);
  const password = entries.find((entry) => entry.startsWith("POSTGRES_PASSWORD="))?.slice("POSTGRES_PASSWORD=".length);
  if (!user || !password) throw new Error("Local PostgreSQL fixture credentials are missing");
  adminUrl.username = user;
  adminUrl.password = password;
}
const root = new pg.Pool({ connectionString: adminUrl.href, max: 1 });
adminUrl.pathname = `/${databaseName}`;
const admin = new pg.Pool({ connectionString: adminUrl.href, max: 3 });
const gatewayUrl = new URL(process.env.SIGNALBOX_POLICY_TEST_GATEWAY_URL ?? "postgresql://sb_gateway_login:gw@127.0.0.1:55433/postgres");
gatewayUrl.pathname = `/${databaseName}`;
const gateway = new pg.Pool({ connectionString: gatewayUrl.href, max: 8 });
const repository = new ArchitectureRepository(gateway);
const objects = new MemoryArtifactStore();
const compiler = new GovernanceBundleCompiler({ objectStore: objects });
const installer = new PostgresPolicyInstaller(admin, repository, objects, compiler);
const pi = createSignalboxGatewayExecutor(gateway as never, { issuer: ISSUER, subject: "agent:pi" });
const other = createSignalboxGatewayExecutor(gateway as never, { issuer: ISSUER, subject: "agent:other" });
const workerIdentity = { issuer: ISSUER, subject: "agent:connector" };
const executor = createSignalboxGatewayExecutor(gateway as never, workerIdentity);
let baseline: CompiledGovernanceBundle;
let restrictive: CompiledGovernanceBundle;
let permissive: CompiledGovernanceBundle;
let otherBaseline: CompiledGovernanceBundle;
let seed: string;

async function resetDomain(): Promise<void> {
  const client = await admin.connect();
  try {
    await client.query(seed);
    await client.query(`SET ROLE modellang_owner;
      UPDATE model_signalbox.principal SET roles='{MEMBER,ADMIN}' WHERE id='${OTHER_ADMIN}';
      INSERT INTO model_signalbox.principal(id,org_id,kind,display_name,status,roles,responsible_owner_id)
        VALUES('00000000-0000-4000-8000-0000000000b9','${OTHER_ORG}','AGENT','Other agent','ACTIVE','{MEMBER}','${OTHER_ADMIN}');
      INSERT INTO model_signalbox.delegation(id,org_id,agent_id,capability,repository_id,connector_id,status)
        VALUES('${otherInput.delegation}','${OTHER_ORG}','00000000-0000-4000-8000-0000000000b9','CREATE_ISSUE','${otherInput.repository}','${otherInput.connector}','ACTIVE');
      INSERT INTO model_signalbox_internal.gateway_principal_binding(issuer,subject,principal_id)
        VALUES('${ISSUER}','agent:other','00000000-0000-4000-8000-0000000000b9');
      RESET ROLE;`);
  } finally {
    client.release();
  }
}

async function storeAndInstall(orgId: string, principalId: string, source: string): Promise<CompiledGovernanceBundle> {
  const compiled = await compiler.compile(orgId, source);
  await repository.saveCompiledBundle(orgId, principalId, compiled);
  await installer.install(orgId, compiled.id, principalId);
  return compiled;
}
const activate = (bundle: CompiledGovernanceBundle) => repository.activateBundle(ORG, bundle.id, ADMIN, objects);

async function waitForPolicyWaiter(): Promise<void> {
  // Observe a real database lock wait, rather than passing a timing-only assertion.
  for (let attempt = 0; attempt < 1_000; attempt++) {
    const result = await admin.query<{ waiting: boolean }>(
      "SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_locks WHERE locktype='advisory' AND NOT granted AND database=(SELECT oid FROM pg_catalog.pg_database WHERE datname=$1)) AS waiting",
      [databaseName],
    );
    if (result.rows[0]?.waiting) return;
  }
  throw new Error("Expected activation/action to wait on the tenant policy lock");
}

async function dispatchIssue(): Promise<{ id: string }> {
  const created = await pi.execute(REQUEST, input, { idempotencyKey: randomUUID() }) as { id: string };
  return await executor.execute(DISPATCH, {
    request: created.id, allowance: "00000000-0000-4000-8000-000000000101", connector: CONNECTOR,
  }, { idempotencyKey: randomUUID() }) as { id: string };
}

beforeAll(async () => {
  await root.query(`CREATE DATABASE "${databaseName}"`);
  const client = await admin.connect();
  try {
    // Cluster roles/login memberships belong to the existing local test fixture.
    const files = (await readdir("generated/signalbox/postgres")).filter((name) => name.endsWith(".sql") && name !== "001_roles.sql").sort();
    for (const file of files) await client.query(await readFile(join("generated/signalbox/postgres", file), "utf8"));
    await client.query("RESET ROLE");
    for (const file of ["sql/phase2_auth.sql", "sql/phase3_worker.sql", "sql/phase5_architecture.sql"]) {
      await client.query(await readFile(file, "utf8"));
      await client.query("RESET ROLE");
    }
    await installPolicyGuards(client);
  } finally {
    client.release();
  }
  seed = await readFile("seed.sql", "utf8");
  await resetDomain();
  const source = await readFile("signalbox.model", "utf8");
  const authorization = "authorize IssueDelegation(actor, delegation, repository, connector);";
  baseline = await storeAndInstall(ORG, ADMIN, source);
  restrictive = await storeAndInstall(ORG, ADMIN, source.replace(authorization, `${authorization}\n  require tenant_title: title != \"blocked-policy-input\";`));
  permissive = await storeAndInstall(ORG, ADMIN, source.replace(authorization,
    "authorize delegation.org == actor.org and repository.org == actor.org and connector.org == actor.org;"));
  otherBaseline = await storeAndInstall(OTHER_ORG, OTHER_ADMIN, source);
  await activate(baseline);
  await repository.activateBundle(OTHER_ORG, otherBaseline.id, OTHER_ADMIN, objects);
}, 120_000);

beforeEach(async () => {
  await resetDomain();
  await activate(baseline);
});

afterAll(async () => {
  try {
    await Promise.all([gateway.end(), admin.end()]);
    await root.query(`DROP DATABASE IF EXISTS "${databaseName}" WITH (FORCE)`);
  } finally {
    await root.end();
  }
});

describe("authoritative current tenant policy", () => {
  it("returns valid public traces for current policies without leaking private provenance", async () => {
    const transport = publicDecisionExecutor(pi);
    await activate(baseline);
    const allowed = await assembleSignalboxPublicDecisionTrace(transport, { action: { operationId: REQUEST, input } });
    expect(allowed.decision).toMatchObject({ applicable: true });
    expect(allowed.decision).not.toHaveProperty("policyBundleId");
    await activate(restrictive);
    const denied = await assembleSignalboxPublicDecisionTrace(transport, { action: { operationId: REQUEST, input } });
    expect(denied.decision).toEqual({ operationId: REQUEST, applicable: false, authority: "none", status: "denied",
      explanation: { kind: "authorization", ruleId: `authorize:${REQUEST}` } });
    expect(await pi.assess(REQUEST, input)).toMatchObject({ policyBundleId: restrictive.id,
      explanation: { kind: "requirement", ruleId: `require:${REQUEST}.tenant_title` } });
    await expect(transport.execute(REQUEST, input, { idempotencyKey: randomUUID() })).rejects.toThrow();
    await activate(baseline);
    const restored = await assembleSignalboxPublicDecisionTrace(transport, { action: { operationId: REQUEST, input } });
    expect(restored.decision.applicable).toBe(true);
  });
  it("changes the same request from allow to deny and back on rollback, without affecting another tenant", async () => {
    expect(await pi.assess(REQUEST, input)).toMatchObject({ applicable: true, policyBundleId: baseline.id });
    await activate(restrictive);
    expect(await pi.assess(REQUEST, input)).toMatchObject({
      applicable: false, status: "notApplicable", policyBundleId: restrictive.id,
      policySourceHash: restrictive.bundle.model.sourceHash,
      baselineSourceHash: baseline.bundle.model.sourceHash,
      explanation: { ruleId: `require:${REQUEST}.tenant_title` },
    });
    await expect(pi.execute(REQUEST, input, { idempotencyKey: randomUUID() })).rejects.toThrow();
    expect(await other.execute(REQUEST, otherInput, { idempotencyKey: randomUUID() })).toMatchObject({ org: OTHER_ORG, status: "READY" });
    await activate(baseline);
    expect(await pi.execute(REQUEST, input, { idempotencyKey: randomUUID() })).toMatchObject({ org: ORG, status: "READY" });
  });

  it("cannot weaken baseline isolation or bypass publishing with reviewer or SQL privileges", async () => {
    await activate(permissive);
    expect(await pi.assess(REQUEST, otherInput)).toMatchObject({ applicable: false, status: "denied" });
    const reviewer = createSignalboxGatewayExecutor(gateway as never, { issuer: ISSUER, subject: "human:dana" });
    expect(await reviewer.assess(REQUEST, input)).toMatchObject({ applicable: false, status: "denied" });
    await expect(repository.activateBundle(ORG, restrictive.id, REVIEWER, objects)).rejects.toThrow();
    await expect(installer.install(ORG, restrictive.id, REVIEWER)).rejects.toThrow();
    await expect(gateway.query("UPDATE signalbox_architecture.governance_bundle SET status='ACTIVE' WHERE id=$1", [restrictive.id])).rejects.toMatchObject({ code: "42501" });
    await expect(gateway.query("DELETE FROM signalbox_architecture.installed_policy")).rejects.toMatchObject({ code: "42501" });
    await expect(gateway.query("SELECT model_signalbox.baseline_request_issue_creation($1,$2,$3,$4,$5)", Object.values(input))).rejects.toMatchObject({ code: "42501" });
    await expect(gateway.query("SELECT model_signalbox.baseline_decide_act_ea693a4d658449fbab5741b8369bc276($1,$2,$3,$4,$5,NULL)", Object.values(input))).rejects.toMatchObject({ code: "42501" });
    const client = await gateway.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT model_signalbox_internal.bind_gateway_identity($1,$2)", [ISSUER, "agent:pi"]);
      await client.query("SELECT set_config('signalbox.org_id',$1,true)", [OTHER_ORG]);
      const result = await client.query("SELECT model_signalbox.decide_act_ea693a4d658449fbab5741b8369bc276($1,$2,$3,$4,$5,NULL) AS decision", Object.values(otherInput));
      expect(result.rows[0].decision).toMatchObject({ applicable: false, policyBundleId: permissive.id });
    } finally {
      await client.query("ROLLBACK");
      client.release();
    }
  });

  it("fails closed for an active bundle without installed decisions, and for no active bundle", async () => {
    const client = await admin.connect();
    try {
      await client.query("SET ROLE modellang_owner");
      await client.query("DELETE FROM signalbox_architecture.installed_policy WHERE bundle_id=$1", [baseline.id]);
      expect(await pi.assess(REQUEST, input)).toMatchObject({ applicable: false, policyBundleId: baseline.id, explanation: { ruleId: "signalbox:active_policy_required" } });
      await expect(pi.execute(REQUEST, input, { idempotencyKey: randomUUID() })).rejects.toThrow();
      await client.query("RESET ROLE");
      await client.query("UPDATE signalbox_architecture.governance_bundle SET status='RETIRED' WHERE id=$1", [baseline.id]);
      expect(await pi.assess(REQUEST, input)).toMatchObject({ applicable: false, policyBundleId: null });
    } finally {
      await client.query("RESET ROLE");
      client.release();
      await installer.install(ORG, baseline.id, ADMIN);
      await activate(baseline);
    }
  });

  it("retains receipt replay/options and binds assessed revisions to the current bundle", async () => {
    const assessed = await pi.assess(REQUEST, input);
    const options = { idempotencyKey: randomUUID(), expectedRevision: assessed.revision, correlationId: "policy-replay", causationId: "policy-parent" };
    const first = await pi.execute(REQUEST, input, options);
    expect(await pi.execute(REQUEST, input, options)).toEqual(first);
    await expect(pi.execute(REQUEST, { ...input, title: "different" }, options)).rejects.toThrow();
    await expect(pi.execute(REQUEST, input, { ...options, expectedRevision: "wrong" })).rejects.toThrow();
    if (!first || typeof first !== "object" || !("id" in first) || typeof first.id !== "string") throw new Error("Request action omitted its identifier");
    const dispatchInput = { request: first.id, allowance: "00000000-0000-4000-8000-000000000101", connector: CONNECTOR };
    const dispatchOptions = { idempotencyKey: randomUUID() };
    const dispatched = await executor.execute(DISPATCH, dispatchInput, dispatchOptions);
    // The consumed allowance and DISPATCHED state cannot make an exact replay fail.
    expect(await executor.execute(DISPATCH, dispatchInput, dispatchOptions)).toEqual(dispatched);
    await activate(permissive);
    expect(await pi.assess(REQUEST, input, { expectedRevision: assessed.revision })).toMatchObject({ applicable: false, status: "stale" });
    await expect(pi.execute(REQUEST, input, options)).rejects.toThrow();
  });

  it("serializes activation after an in-flight action and applies the new rule to the next action", async () => {
    const client = await gateway.connect();
    let activation: Promise<unknown> | undefined;
    try {
      await client.query("BEGIN");
      await client.query("SELECT model_signalbox_internal.bind_gateway_identity($1,$2)", [ISSUER, "agent:pi"]);
      await client.query("SELECT set_config('modellang.idempotency_key',$1,true)", [randomUUID()]);
      const action = await client.query("SELECT model_signalbox.request_issue_creation($1,$2,$3,$4,$5) AS result", Object.values(input));
      expect(action.rows[0].result).toMatchObject({ status: "READY" });
      activation = activate(restrictive);
      await waitForPolicyWaiter();
      expect(await other.execute(REQUEST, otherInput, { idempotencyKey: randomUUID() })).toMatchObject({ org: OTHER_ORG });
      await client.query("COMMIT");
      await activation;
      expect(await pi.assess(REQUEST, input)).toMatchObject({ applicable: false, policyBundleId: restrictive.id });
    } finally {
      await client.query("ROLLBACK");
      client.release();
      await activation;
    }
  });

  it("sees the committed replacement when activation wins the tenant lock", async () => {
    const client = await gateway.connect();
    let rejectedAction: Promise<void> | undefined;
    try {
      await client.query("BEGIN");
      await client.query("SELECT * FROM signalbox_architecture.activate_bundle($1,$2,$3,$4,$5)",
        [ORG, restrictive.id, ADMIN, restrictive.bundle.bundleHash, restrictive.bundle.model.sourceHash]);
      rejectedAction = expect(pi.execute(REQUEST, input, { idempotencyKey: randomUUID() })).rejects.toThrow();
      await waitForPolicyWaiter();
      await client.query("COMMIT");
      await rejectedAction;
      expect(await pi.assess(REQUEST, input)).toMatchObject({ applicable: false, policyBundleId: restrictive.id });
    } finally {
      await client.query("ROLLBACK");
      client.release();
      await rejectedAction;
    }
  });

  it("invalidates queued work from an older run policy before any connector effect", async () => {
    const execution = await dispatchIssue();
    const claim = await gateway.query("SELECT * FROM model_signalbox_worker.claim_execution($1,$2,$3,60)", [ISSUER, "agent:connector", "policy-claim"]);
    const token = claim.rows[0].claim_token;
    const confirmationSql = "SELECT model_signalbox_worker.confirm_execution_claim($1,$2,$3,$4,$5) AS allowed";
    const confirmationInput = [ISSUER, "agent:connector", "policy-claim", execution.id, token];
    expect((await gateway.query(confirmationSql, confirmationInput)).rows[0].allowed).toBe(true);
    await activate(restrictive);
    expect((await gateway.query(confirmationSql, confirmationInput)).rows[0].allowed).toBe(false);
    // A reused executor (or immutable run manifest) carries no override authority.
    await expect(pi.execute(REQUEST, input, { idempotencyKey: randomUUID() })).rejects.toThrow();
  });

  it("holds publishing behind a worker effect and still records the outcome after activation", async () => {
    const execution = await dispatchIssue();
    const effects = new EventEmitter();
    const entered = once(effects, "entered");
    const released = once(effects, "released");
    const worker = new SignalboxWorker({
      pool: gateway, identity: workerIdentity, workerId: "policy-effect", leaseSeconds: 60,
      connectors: new Map([[CONNECTOR, { kind: "GITHUB" as const, async execute() { effects.emit("entered"); await released; return "https://example.invalid/issues/7"; } }]]),
    });
    const running = worker.runOnce();
    let activation: Promise<unknown> | undefined;
    try {
      await Promise.race([entered, running.then(() => { throw new Error("Worker ended before entering its connector effect"); })]);
      activation = activate(restrictive);
      await waitForPolicyWaiter();
      effects.emit("released");
      await Promise.all([running, activation]);
      const client = await admin.connect();
      try {
        await client.query("SET ROLE modellang_owner");
        const result = await client.query("SELECT status, external_reference FROM model_signalbox.execution WHERE id=$1", [execution.id]);
        expect(result.rows[0]).toEqual({ status: "SUCCEEDED", external_reference: "https://example.invalid/issues/7" });
        const activity = await gateway.query("SELECT * FROM signalbox_architecture.action_evidence($1,$2)", [ISSUER, "human:opsadmin"]);
        expect(activity.rows).toEqual(expect.arrayContaining([expect.objectContaining({
          result: expect.objectContaining({ execution: expect.objectContaining({ id: execution.id, status: "SUCCEEDED", externalReference: "https://example.invalid/issues/7" }) }),
        })]));
      } finally { await client.query("RESET ROLE"); client.release(); }
    } finally {
      effects.emit("released");
      await Promise.all([running, activation]);
    }
  });

  it("refuses startup when its baseline differs or generated SQL has overwritten policy guards", async () => {
    const startup = "SELECT signalbox_architecture.assert_policy_runtime($1)";
    await gateway.query(startup, [baseline.bundle.model.sourceHash]);
    await expect(gateway.query(startup, [`sha256:${"0".repeat(64)}`])).rejects.toMatchObject({
      code: "55000", message: "SB_POLICY_RUNTIME_NOT_INSTALLED",
    });
    const client = await admin.connect();
    const definitions: string[] = [];
    try {
      await client.query("SET ROLE modellang_owner");
      const saved = await client.query<{ definition: string }>(
        "SELECT pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(function_identity)) AS definition FROM signalbox_architecture.policy_runtime_function",
      );
      definitions.push(...saved.rows.map((row) => row.definition));
      // Exercise the actual deployment mistake, without rewriting SQL text.
      await client.query(await readFile("generated/signalbox/postgres/003_actions.sql", "utf8"));
      await expect(gateway.query(startup, [baseline.bundle.model.sourceHash])).rejects.toMatchObject({
        code: "55000", message: "SB_POLICY_RUNTIME_CHANGED",
      });
    } finally {
      for (const definition of definitions) await client.query(definition);
      await client.query("RESET ROLE");
      client.release();
    }
    await gateway.query(startup, [baseline.bundle.model.sourceHash]);
    await activate(restrictive);
    await expect(pi.execute(REQUEST, input, { idempotencyKey: randomUUID() })).rejects.toThrow();
  });

  it("returns tenant-scoped structured evidence without copying sensitive action inputs", async () => {
    await pi.execute(REQUEST, input, { idempotencyKey: randomUUID() });
    await activate(restrictive);
    await pi.assess(REQUEST, input);
    const activity = await gateway.query("SELECT * FROM signalbox_architecture.action_evidence($1,$2,100)", [ISSUER, "human:opsadmin"]);
    expect(activity.rows).toEqual(expect.arrayContaining([
      expect.objectContaining({ decision: "executed", policy_bundle_id: baseline.id, result: expect.objectContaining({ kind: "action", status: "READY" }) }),
      expect.objectContaining({ decision: "notApplicable", policy_bundle_id: restrictive.id, result: expect.objectContaining({ kind: "assessment", explanation: { kind: "requirement", ruleId: `require:${REQUEST}.tenant_title` } }) }),
    ]));
    expect(JSON.stringify(activity.rows)).not.toContain(input.body);
    expect(JSON.stringify(activity.rows)).not.toContain(input.title);
    expect((await gateway.query("SELECT * FROM signalbox_architecture.action_evidence($1,$2,100)", [ISSUER, "human:outsider"])).rows).toEqual([]);
    await expect(gateway.query("SELECT * FROM signalbox_architecture.action_evidence($1,$2,100)", [ISSUER, "agent:pi"])).rejects.toMatchObject({ code: "42501" });
  });
});
