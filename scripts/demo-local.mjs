// Local-only proof environment. Run from the repository root after building the host.
// Evidence, database, login role, and object bucket remain available after shutdown.
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { chmod, mkdtemp, readFile, readdir, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { CreateBucketCommand, S3Client } from "@aws-sdk/client-s3";
import { exportJWK, exportPKCS8, generateKeyPair, SignJWT } from "jose";
import { Pool } from "pg";
import { createSignalboxBoundary } from "../dist/boundary.mjs";
import { createSignalboxNodeServer } from "../dist/server.mjs";
import { GovernanceBundleCompiler } from "../dist/architecture/bundle-compiler.mjs";
import { S3ArtifactStore } from "../dist/architecture/object-store.mjs";
import { ArchitectureRepository } from "../dist/architecture/repository.mjs";
import { PostgresPolicyInstaller } from "../dist/architecture/policy-installer.mjs";
import { installPolicyGuards } from "../dist/architecture/policy-guard.mjs";

const appOrigin = "http://127.0.0.1:54310";
const issuer = "http://127.0.0.1:54311";
const audience = "signalbox-local-demo";
const container = "sb-pg16";
const orgId = "00000000-0000-4000-8000-0000000000a1";
const adminId = "00000000-0000-4000-8000-0000000000b4";
const reviewerId = "00000000-0000-4000-8000-0000000000b2";
const agentId = "00000000-0000-4000-8000-0000000000b1";
const workerId = "00000000-0000-4000-8000-0000000000b6";
const directory = await mkdtemp(join(tmpdir(), "signalbox-local-demo-"));
await chmod(directory, 0o700);
const pools = [];
let oidcServer;
let appServer;
let s3;
let closing;

async function privateFile(name, value) {
  const path = join(directory, name);
  await writeFile(path, value, { encoding: "utf8", mode: 0o600 });
  return path;
}

function connectionUrl(connection) {
  const url = new URL(`postgresql://127.0.0.1:${connection.port}/${connection.database}`);
  url.username = connection.user;
  url.password = connection.password;
  return url.href;
}

function listen(server, port) {
  return new Promise((resolvePromise, reject) => {
    const error = (cause) => reject(cause);
    server.once("error", error);
    server.listen(port, "127.0.0.1", () => {
      server.removeListener("error", error);
      resolvePromise();
    });
  });
}

async function close() {
  closing ??= (async () => {
    await Promise.all([appServer, oidcServer].filter(Boolean).map((server) => new Promise((done) => {
      server.close(done);
      server.closeIdleConnections();
    })));
    await Promise.all(pools.map((pool) => pool.end()));
    s3?.destroy();
  })();
  return closing;
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, () => { void close().then(() => process.exit(0)); });
}

async function main() {
  // Capture container credentials in memory only; never echo docker inspect output.
  const [inspection] = JSON.parse(execFileSync("docker", ["inspect", container], {
    encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  }));
  const environment = Object.fromEntries(inspection.Config.Env.map((entry) => {
    const index = entry.indexOf("=");
    return [entry.slice(0, index), entry.slice(index + 1)];
  }));
  const port = Number(inspection.NetworkSettings.Ports["5432/tcp"]?.[0]?.HostPort);
  if (!environment.POSTGRES_USER || !environment.POSTGRES_PASSWORD || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("The local PostgreSQL container must expose its configured credentials and TCP port.");
  }
  const suffix = `${Date.now().toString(36)}_${randomBytes(6).toString("hex")}`;
  const database = `sb_local_demo_${suffix}`;
  const gatewayUser = `sb_demo_gateway_${suffix}`;
  const gatewayPassword = randomBytes(32).toString("hex");
  const rootConnection = {
    host: "127.0.0.1", port, user: environment.POSTGRES_USER, password: environment.POSTGRES_PASSWORD,
    database: environment.POSTGRES_DB ?? environment.POSTGRES_USER,
  };
  const rootPool = new Pool(rootConnection);
  try {
    await rootPool.query(`CREATE DATABASE "${database}"`);
    await rootPool.query(`CREATE ROLE "${gatewayUser}" LOGIN PASSWORD '${gatewayPassword}'`);
  } finally {
    await rootPool.end();
  }
  const adminConnection = { ...rootConnection, database };
  const gatewayConnection = { host: "127.0.0.1", port, database, user: gatewayUser, password: gatewayPassword };
  const adminPool = new Pool(adminConnection);
  pools.push(adminPool);
  // Save recovery coordinates before applying any migrations. They remain private on failure.
  await privateFile("database.json", JSON.stringify({
    container, database, gatewayRole: gatewayUser,
    databaseUrl: connectionUrl(gatewayConnection), adminDatabaseUrl: connectionUrl(adminConnection),
  }, null, 2));
  const migrationClient = await adminPool.connect();
  try {
    const generated = (await readdir("generated/signalbox/postgres")).filter((name) => name.endsWith(".sql")).sort();
    if (generated.length === 0) throw new Error("Generated PostgreSQL artifacts are unavailable.");
    const migrations = [
      ...generated.map((name) => join("generated/signalbox/postgres", name)),
      "sql/phase2_auth.sql", "sql/phase3_worker.sql", "sql/phase5_architecture.sql", "seed.sql",
    ];
    for (const path of migrations) {
      await migrationClient.query(await readFile(path, "utf8"));
      await migrationClient.query("RESET ROLE");
    }
    await migrationClient.query(`GRANT modellang_gateway TO "${gatewayUser}"`);
    await migrationClient.query(
      `INSERT INTO model_signalbox_internal.gateway_principal_binding(issuer,subject,principal_id)
       VALUES ($1,'human:admin',$2),($1,'human:reviewer',$3),($1,'agent:pi',$4),($1,'agent:connector',$5)`,
      [issuer, adminId, reviewerId, agentId, workerId],
    );
    await installPolicyGuards(migrationClient);
  } finally {
    migrationClient.release();
  }
  const pool = new Pool(gatewayConnection);
  pools.push(pool);
  const baselineIr = JSON.parse(await readFile("generated/signalbox/model.ir.json", "utf8"));
  await pool.query("SELECT signalbox_architecture.assert_policy_runtime($1)", [baselineIr.model.sourceHash]);

  const { privateKey, publicKey } = await generateKeyPair("RS256", { extractable: true });
  const kid = `signalbox-local-${suffix}`;
  const jwk = { ...await exportJWK(publicKey), kid, alg: "RS256", use: "sig" };
  const jwks = { keys: [jwk] };
  await privateFile("oidc-private.pem", await exportPKCS8(privateKey));
  await privateFile("jwks.json", JSON.stringify(jwks));
  oidcServer = createServer((request, response) => {
    if (request.method === "GET" && request.url === "/.well-known/jwks.json") {
      response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
      response.end(JSON.stringify(jwks));
      return;
    }
    response.writeHead(404);
    response.end();
  });
  await listen(oidcServer, 54311);
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
  const mint = (subject) => new SignJWT({}).setProtectedHeader({ alg: "RS256", kid })
    .setIssuer(issuer).setAudience(audience).setSubject(subject).setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000)).sign(privateKey);
  const [adminToken, reviewerToken] = await Promise.all([mint("human:admin"), mint("human:reviewer")]);

  const objectConfiguration = {
    endpoint: "http://127.0.0.1:59000", region: "us-east-1", forcePathStyle: true,
    bucket: `signalbox-local-demo-${suffix.replaceAll("_", "-")}`,
    accessKeyId: "signalbox-local-proof", secretAccessKey: "signalbox-local-proof-only",
  };
  s3 = new S3Client({
    endpoint: objectConfiguration.endpoint, region: objectConfiguration.region, forcePathStyle: true,
    credentials: { accessKeyId: objectConfiguration.accessKeyId, secretAccessKey: objectConfiguration.secretAccessKey },
  });
  await s3.send(new CreateBucketCommand({ Bucket: objectConfiguration.bucket }));
  const objectStore = new S3ArtifactStore({ ...objectConfiguration, client: s3 });
  const compiler = new GovernanceBundleCompiler({ objectStore, compiler: resolve("node_modules/.bin/modelc") });
  const repository = new ArchitectureRepository(pool);
  const installer = new PostgresPolicyInstaller(adminPool, repository, objectStore, compiler);
  const baselineSource = await readFile("signalbox.model", "utf8");
  const restriction = "and delegation.capability == Capability.REQUEST_PRODUCTION_DEPLOY";
  if (baselineSource.split(restriction).length !== 2) throw new Error("The fixed production policy restriction point must be unique.");
  const restrictedSource = baselineSource.replace(restriction, `${restriction}\n    and false`);
  const baselineSourcePath = await privateFile("baseline.model", baselineSource);
  const restrictedSourcePath = await privateFile("restricted.model", restrictedSource);
  const compiled = await compiler.compile(orgId, baselineSource);
  const baselineBundleId = await repository.saveCompiledBundle(orgId, adminId, compiled);
  await installer.install(orgId, baselineBundleId, adminId);
  await repository.activateBundle(orgId, baselineBundleId, adminId, objectStore);

  const boundary = createSignalboxBoundary({
    pool, publicOrigin: appOrigin, identity: { oidc: { issuer, audience } },
    governanceStudio: {
      repository, compiler, objectStore, installer,
      activity: async (identity) => {
        const result = await pool.query("SELECT * FROM signalbox_architecture.action_evidence($1,$2)", [identity.issuer, identity.subject]);
        return result.rows.map((row) => ({
          id: row.id, operationId: row.operation_id, decision: row.decision,
          policyBundleId: row.policy_bundle_id, policySourceHash: row.policy_source_hash,
          createdAt: row.created_at, result: row.result,
        }));
      },
    },
  });
  const agentCredential = await boundary.agentTokens.issue(
    { issuer, subject: "human:admin" }, agentId, { label: "local-demo-proof", expiresAt },
  );
  appServer = createSignalboxNodeServer(boundary, appOrigin);
  await listen(appServer, 54310);
  const configuration = {
    directory, appOrigin, readyUrl: `${appOrigin}/studio`, issuer, audience, expiresAt: expiresAt.toISOString(),
    container, database, databaseUrl: connectionUrl(gatewayConnection), adminDatabaseUrl: connectionUrl(adminConnection),
    objectStore: objectConfiguration,
    admin: { issuer, subject: "human:admin", principalId: adminId, token: adminToken },
    reviewer: { issuer, subject: "human:reviewer", principalId: reviewerId, token: reviewerToken },
    agent: { issuer: boundary.agentTokens.issuer, subject: `agent:${agentId}`, principalId: agentId, token: agentCredential.token, credentialId: agentCredential.id },
    worker: { issuer, subject: "agent:connector", principalId: workerId },
    seededAgent: { issuer, subject: "agent:pi", principalId: agentId },
    orgId, baselineBundleId, baselineSourceHash: compiled.bundle.model.sourceHash, baselineSourcePath, restrictedSourcePath,
    resources: {
      repositoryId: "00000000-0000-4000-8000-0000000000d1", connectorId: "00000000-0000-4000-8000-0000000000c1",
      issueDelegationId: "00000000-0000-4000-8000-0000000000f1", allowanceId: "00000000-0000-4000-8000-000000000101",
      stagingEnvironmentId: "00000000-0000-4000-8000-0000000000e2", productionEnvironmentId: "00000000-0000-4000-8000-0000000000e1",
    },
  };
  await privateFile("config.json", JSON.stringify(configuration, null, 2));
  // Ready means real HTTP/JWKS authentication and persisted policy are available.
  for (const [token, canAdminister] of [[adminToken, true], [reviewerToken, false]]) {
    const response = await fetch(`${appOrigin}/studio/api/bootstrap`, { headers: { authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(`Local bootstrap returned HTTP ${response.status}.`);
    const bootstrap = await response.json();
    if (bootstrap.active?.id !== baselineBundleId || bootstrap.permissions?.canAdministerGovernance !== canAdminister) {
      throw new Error("Local bootstrap did not expose the persisted policy and current permission.");
    }
  }
  const agentIdentity = await boundary.authenticate(agentCredential.token);
  if (agentIdentity?.principalId !== agentId || agentIdentity.kind !== "AGENT") throw new Error("The issued local agent credential did not authenticate.");
  await privateFile("ready.json", JSON.stringify({ readyAt: new Date().toISOString(), baselineBundleId, adminAuthenticated: true, reviewerReadOnly: true, agentAuthenticated: true }, null, 2));
  process.stdout.write(`${directory}\n${configuration.readyUrl}\n`);
}

try {
  await main();
} catch (error) {
  await privateFile("failure.json", JSON.stringify({ name: error?.name, message: error?.message, stack: error?.stack }, null, 2));
  // Error details can contain private connection data, so print only their directory.
  process.stderr.write(`${directory}\n`);
  await close();
  process.exitCode = 1;
}
