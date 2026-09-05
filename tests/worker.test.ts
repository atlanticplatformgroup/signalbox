import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, readlink, rm, writeFile } from "node:fs/promises";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { exportPKCS8, generateKeyPair } from "jose";
import pg from "pg";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import { PreconditionError } from "../generated/signalbox/dist/errors.js";
import { ConnectorFailure, type ExecutionClaim, type ExecutionConnector } from "../src/connectors/connector.mjs";
import { GitHubAppConnector } from "../src/connectors/github-app.mjs";
import { PostgreSqlMigrationConnector } from "../src/connectors/postgresql-migration.mjs";
import { StaticSiteConnector } from "../src/connectors/static-site.mjs";
import { SignalboxWorker } from "../src/worker.mjs";

const ISSUER = "https://signalbox.test";
const CONNECTOR_GITHUB = "00000000-0000-4000-8000-0000000000c1";
const CONNECTOR_DEPLOY = "00000000-0000-4000-8000-0000000000c2";
const CONNECTOR_DATABASE = "00000000-0000-4000-8000-0000000000c3";
const REPOSITORY = "00000000-0000-4000-8000-0000000000d1";
const ENV_STAGING = "00000000-0000-4000-8000-0000000000e2";
const ENV_DATABASE = "00000000-0000-4000-8000-0000000000e3";
const DELEGATION_ISSUE = "00000000-0000-4000-8000-0000000000f1";
const DELEGATION_STAGING = "00000000-0000-4000-8000-0000000000f3";
const DELEGATION_MIGRATION = "00000000-0000-4000-8000-0000000000f5";
const ALLOWANCE = "00000000-0000-4000-8000-000000000101";
const OP = {
  requestIssue: "action:act_ea693a4d658449fbab5741b8369bc276",
  requestStaging: "action:act_1388eb9f38684fa0830f60156cdba497",
  requestMigration: "action:act_411bfff32560406186bd2d442f1ecf3b",
  approveMigration: "action:act_4c170dfcb0224cb8aaf078fe6b6ef23d",
  dispatchIssue: "action:act_cbb72fd307704ab3927aa4bea8112fbf",
  dispatchStaging: "action:act_3e26a4d454634bf3a2058204146d7c45",
  dispatchMigration: "action:act_70d3862584094631aca61e9db664d991",
} as const;

const postgresFiles = [
  "generated/signalbox/postgres/001_roles.sql",
  "generated/signalbox/postgres/002_schema.sql",
  "generated/signalbox/postgres/003_actions.sql",
  "generated/signalbox/postgres/003_decisions.sql",
  "generated/signalbox/postgres/003_queries.sql",
  "generated/signalbox/postgres/003_consumers.sql",
  "generated/signalbox/postgres/004_grants.sql",
  "generated/signalbox/postgres/005_seed.sql",
  "sql/phase2_auth.sql",
  "sql/phase3_worker.sql",
  "seed.sql",
] as const;

function psql(database: string, statement: string): string {
  return execFileSync(
    "docker",
    ["exec", "-i", "sb-pg16", "psql", "-U", "nebius_admin", "-d", database, "-tAq", "-v", "ON_ERROR_STOP=1", "-f", "-"],
    { input: statement, encoding: "utf8" },
  ).trim();
}

function ownerSql(statement: string): string {
  return psql("sb_worker", `SET ROLE modellang_owner;\n${statement}`);
}

let gatewayPool: pg.Pool;
let targetPool: pg.Pool;
let githubServer: Server;
let githubOrigin: string;
let githubPrivateKey: string;
let temporaryDirectories: string[] = [];
let githubIssues: Array<{ body: string; html_url: string }> = [];
let githubPulls: Array<{ body: string; html_url: string }> = [];
let githubPosts = 0;
let delayNextCreate = false;
let capturedHeaders: Record<string, string | undefined> = {};
let serial = 0;
const activeSignal = new AbortController().signal;
const nextKey = () => `worker-${Date.now()}-${serial++}`;

beforeAll(async () => {
  psql("postgres", "DROP DATABASE IF EXISTS sb_worker WITH (FORCE);\nCREATE DATABASE sb_worker;");
  for (const file of postgresFiles) psql("sb_worker", await readFile(file, "utf8"));
  psql("postgres", `
    DO $body$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='sb_target_login') THEN
        CREATE ROLE sb_target_login LOGIN PASSWORD 'target';
      END IF;
    END $body$;
    DROP DATABASE IF EXISTS sb_target WITH (FORCE);
    CREATE DATABASE sb_target OWNER modellang_owner;
  `);
  psql("sb_target", "SET ROLE modellang_owner; GRANT USAGE, CREATE ON SCHEMA public TO sb_target_login;");
  gatewayPool = new pg.Pool({ host: "127.0.0.1", port: 55433, database: "sb_worker", user: "sb_gateway_login", password: "gw", max: 8 });
  targetPool = new pg.Pool({ host: "127.0.0.1", port: 55433, database: "sb_target", user: "sb_target_login", password: "target", max: 4 });
  const { privateKey } = await generateKeyPair("RS256", { extractable: true });
  githubPrivateKey = await exportPKCS8(privateKey);
  githubServer = createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.method === "POST" && url.pathname === "/app/installations/7/access_tokens") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({ token: "installation-token", expires_at: new Date(Date.now() + 3_600_000).toISOString() }));
      return;
    }
    const isIssues = url.pathname === "/repos/acme/web/issues";
    const isPulls = url.pathname === "/repos/acme/web/pulls";
    if (request.method === "GET" && (isIssues || isPulls)) {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify(isIssues ? githubIssues : githubPulls));
      return;
    }
    if (request.method === "POST" && (isIssues || isPulls)) {
      let body = "";
      for await (const chunk of request) body += chunk;
      const parsed: unknown = JSON.parse(body);
      if (!parsed || typeof parsed !== "object" || !("body" in parsed) || typeof parsed.body !== "string") {
        response.statusCode = 400;
        response.end();
        return;
      }
      githubPosts += 1;
      capturedHeaders = {
        idempotency: headerValue(request.headers["idempotency-key"]),
        correlation: headerValue(request.headers["x-signalbox-correlation-id"]),
        causation: headerValue(request.headers["x-signalbox-causation-id"]),
      };
      const reference = isIssues ? `http://github.test/acme/web/issues/${githubIssues.length + 1}` : `http://github.test/acme/web/pull/${githubPulls.length + 1}`;
      (isIssues ? githubIssues : githubPulls).push({ body: parsed.body, html_url: reference });
      const send = () => {
        response.setHeader("content-type", "application/json");
        response.end(JSON.stringify({ body: parsed.body, html_url: reference }));
      };
      if (delayNextCreate) delayNextCreate = false;
      else send();
      return;
    }
    response.statusCode = 404;
    response.end();
  });
  await new Promise<void>((resolveListen) => githubServer.listen(0, "127.0.0.1", resolveListen));
  const address = githubServer.address();
  if (!address || typeof address === "string") throw new Error("GitHub test server did not bind");
  githubOrigin = `http://127.0.0.1:${address.port}/`;
});

beforeEach(async () => {
  psql("sb_worker", await readFile("seed.sql", "utf8"));
  psql("sb_target", "SET ROLE modellang_owner; DROP SCHEMA public CASCADE; CREATE SCHEMA public AUTHORIZATION modellang_owner; GRANT USAGE, CREATE ON SCHEMA public TO sb_target_login;");
  githubIssues = [];
  githubPulls = [];
  githubPosts = 0;
  delayNextCreate = false;
  capturedHeaders = {};
  for (const directory of temporaryDirectories) await rm(directory, { recursive: true, force: true });
  temporaryDirectories = [];
});

afterAll(async () => {
  for (const directory of temporaryDirectories) await rm(directory, { recursive: true, force: true });
  await gatewayPool?.end();
  await targetPool?.end();
  if (githubServer) await new Promise<void>((resolveClose) => githubServer.close(() => resolveClose()));
});

function headerValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

const asPrincipal = (subject: string) => createSignalboxGatewayExecutor(gatewayPool as never, { issuer: ISSUER, subject });
const pi = () => asPrincipal("agent:pi");
const dana = () => asPrincipal("human:dana");

function githubConnector(): GitHubAppConnector {
  return new GitHubAppConnector({
    appId: "1",
    installationId: "7",
    privateKeyPem: githubPrivateKey,
    apiBaseUrl: githubOrigin,
  });
}

function worker(connectors: ReadonlyMap<string, ExecutionConnector>, workerId = nextKey(), overrides: Partial<{
  connectorTimeoutMs: number;
  maxAttempts: number;
}> = {}): SignalboxWorker {
  return new SignalboxWorker({
    pool: gatewayPool,
    identity: { issuer: ISSUER, subject: "agent:connector" },
    workerId,
    connectors,
    leaseSeconds: 5,
    connectorTimeoutMs: overrides.connectorTimeoutMs ?? 1_000,
    maxAttempts: overrides.maxAttempts ?? 3,
    retryBaseMs: 1,
    retryMaxMs: 1,
  });
}

async function dispatchIssue(): Promise<{ requestId: string; executionId: string }> {
  const request = await pi().execute(
    OP.requestIssue,
    { delegation: DELEGATION_ISSUE, repository: REPOSITORY, connector: CONNECTOR_GITHUB, title: "Worker issue", body: "Created durably" },
    { idempotencyKey: nextKey(), correlationId: "corr-issue", causationId: "cause-issue" },
  ) as { id: string };
  const execution = await asPrincipal("agent:connector").execute(
    OP.dispatchIssue,
    { request: request.id, allowance: ALLOWANCE, connector: CONNECTOR_GITHUB },
    { idempotencyKey: nextKey(), correlationId: "corr-dispatch", causationId: "cause-dispatch" },
  ) as { id: string };
  return { requestId: request.id, executionId: execution.id };
}

function directClaim(kind: "ISSUE" | "PULL_REQUEST", executionId: string): ExecutionClaim {
  return {
    executionId,
    claimToken: "00000000-0000-4000-8000-000000000099",
    attemptCount: 1,
    requestKind: kind,
    connectorId: CONNECTOR_GITHUB,
    connectorKind: "GITHUB",
    payload: kind === "ISSUE"
      ? { owner: "acme", repository: "web", title: "Issue", body: "Body" }
      : { owner: "acme", repository: "web", title: "Pull", headBranch: "feature", baseBranch: "main" },
    correlationId: "corr-direct",
    causationId: "cause-direct",
  };
}

describe.sequential("Phase 3 connector execution", () => {
  it("creates GitHub issues and pull requests idempotently with trace metadata", async () => {
    const connector = githubConnector();
    const issue = directClaim("ISSUE", "00000000-0000-4000-8000-000000000011");
    const pull = directClaim("PULL_REQUEST", "00000000-0000-4000-8000-000000000012");
    expect(await connector.execute(issue, activeSignal)).toContain("/issues/1");
    expect(await connector.execute(issue, activeSignal)).toContain("/issues/1");
    expect(await connector.execute(pull, activeSignal)).toContain("/pull/1");
    expect(githubPosts).toBe(2);
    expect(capturedHeaders).toEqual({
      idempotency: pull.executionId,
      correlation: "corr-direct",
      causation: "cause-direct",
    });
  });

  it("leases one execution to one of two concurrent workers", async () => {
    const { executionId } = await dispatchIssue();
    const connectors = new Map([[CONNECTOR_GITHUB, githubConnector()]]);
    const results = await Promise.all([worker(connectors, "worker-a").runOnce(), worker(connectors, "worker-b").runOnce()]);
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(githubPosts).toBe(1);
    expect(ownerSql(`SELECT status || ':' || external_reference FROM model_signalbox.execution WHERE id='${executionId}';`)).toContain("SUCCEEDED:http://github.test/");
    expect(capturedHeaders).toMatchObject({ idempotency: executionId, correlation: "corr-dispatch", causation: "cause-dispatch" });
  });

  it("recovers a lost GitHub response without duplicating the external effect", async () => {
    const { executionId } = await dispatchIssue();
    delayNextCreate = true;
    const runner = worker(new Map([[CONNECTOR_GITHUB, githubConnector()]]), "worker-recovery", { connectorTimeoutMs: 100 });
    expect(await runner.runOnce()).toBe(true);
    expect(githubPosts).toBe(1);
    ownerSql(`UPDATE model_signalbox_worker.execution_claim SET leased_until=now(), next_attempt_at=now() WHERE execution_id='${executionId}';`);
    expect(await runner.runOnce()).toBe(true);
    expect(githubPosts).toBe(1);
    expect(ownerSql(`SELECT status FROM model_signalbox.execution WHERE id='${executionId}';`)).toBe("SUCCEEDED");
  });

  it("recovers instead of repeating an effect when its ledger transaction fails", async () => {
    const { executionId } = await dispatchIssue();
    await targetPool.query("CREATE TABLE public.remote_effect(id serial PRIMARY KEY, execution_id uuid NOT NULL)");
    const connector: ExecutionConnector = {
      kind: "GITHUB",
      async execute(claim) {
        const result = await targetPool.query<{ id: number }>(
          "INSERT INTO public.remote_effect(execution_id) VALUES ($1) RETURNING id",
          [claim.executionId],
        );
        return `effect:${result.rows[0]!.id}`;
      },
      async recover(claim) {
        const result = await targetPool.query<{ id: number }>(
          "SELECT id FROM public.remote_effect WHERE execution_id=$1 ORDER BY id LIMIT 1",
          [claim.executionId],
        );
        return result.rows[0] ? `effect:${result.rows[0].id}` : undefined;
      },
    };
    const runner = worker(new Map([[CONNECTOR_GITHUB, connector]]), "worker-ledger-gap");
    ownerSql(`
      CREATE FUNCTION model_signalbox_worker.reject_effect_record() RETURNS trigger
      LANGUAGE plpgsql AS $body$ BEGIN RAISE EXCEPTION 'ledger unavailable'; END $body$;
      CREATE TRIGGER reject_effect_record BEFORE UPDATE OF effect_reference
      ON model_signalbox_worker.execution_claim FOR EACH ROW
      EXECUTE FUNCTION model_signalbox_worker.reject_effect_record();
    `);
    try {
      await runner.runOnce();
      expect((await targetPool.query("SELECT count(*)::int AS count FROM public.remote_effect")).rows[0]?.count).toBe(1);
      expect(ownerSql(`SELECT last_error_code || ':' || COALESCE(effect_reference, 'none')
        FROM model_signalbox_worker.execution_claim WHERE execution_id='${executionId}';`)).toBe("RECOVERY_REQUIRED:none");
      expect(ownerSql(`SELECT status FROM model_signalbox.execution WHERE id='${executionId}';`)).toBe("PENDING");
    } finally {
      ownerSql(`
        DROP TRIGGER reject_effect_record ON model_signalbox_worker.execution_claim;
        DROP FUNCTION model_signalbox_worker.reject_effect_record();
      `);
    }
    ownerSql(`UPDATE model_signalbox_worker.execution_claim SET leased_until=now(), next_attempt_at=now() WHERE execution_id='${executionId}';`);
    await runner.runOnce();
    expect((await targetPool.query("SELECT count(*)::int AS count FROM public.remote_effect")).rows[0]?.count).toBe(1);
    expect(ownerSql(`SELECT status || ':' || external_reference FROM model_signalbox.execution WHERE id='${executionId}';`)).toBe("SUCCEEDED:effect:1");
  });

  it("publishes a static release atomically and completes the deployment", async () => {
    const root = await mkdtemp(join(tmpdir(), "signalbox-static-"));
    temporaryDirectories.push(root);
    const source = join(root, "source");
    const published = join(root, "published");
    await mkdir(source);
    await writeFile(join(source, "index.html"), "<h1>Signalbox</h1>\n");
    const request = await pi().execute(
      OP.requestStaging,
      { delegation: DELEGATION_STAGING, environment: ENV_STAGING, connector: CONNECTOR_DEPLOY, commitSha: "a".repeat(40) },
      { idempotencyKey: nextKey() },
    ) as { id: string };
    const execution = await asPrincipal("agent:connector").execute(
      OP.dispatchStaging,
      { request: request.id, allowance: ALLOWANCE, connector: CONNECTOR_DEPLOY },
      { idempotencyKey: nextKey() },
    ) as { id: string };
    const connector = new StaticSiteConnector({ sourceDirectory: source, publishDirectory: published, publicBaseUrl: "https://staging.example/" });
    await worker(new Map([[CONNECTOR_DEPLOY, connector]])).runOnce();
    expect(await readFile(join(published, "releases", execution.id, "index.html"), "utf8")).toContain("Signalbox");
    expect(await readlink(join(published, "current"))).toBe(`releases/${execution.id}`);
    expect(ownerSql(`SELECT status FROM model_signalbox.execution WHERE id='${execution.id}';`)).toBe("SUCCEEDED");
  });

  it("applies an approved PostgreSQL migration transactionally and replays its ledger", async () => {
    const root = await mkdtemp(join(tmpdir(), "signalbox-migration-"));
    temporaryDirectories.push(root);
    const migrationName = "20260829_create_widget";
    const migrationSql = "CREATE TABLE public.widget(id integer PRIMARY KEY);\nINSERT INTO public.widget(id) VALUES (1);\n";
    const migrationSha = createHash("sha256").update(migrationSql).digest("hex");
    await writeFile(join(root, `${migrationName}.sql`), migrationSql);
    const request = await pi().execute(
      OP.requestMigration,
      { delegation: DELEGATION_MIGRATION, environment: ENV_DATABASE, connector: CONNECTOR_DATABASE, migrationName, migrationSha },
      { idempotencyKey: nextKey() },
    ) as { id: string };
    await dana().execute(OP.approveMigration, { request: request.id }, { idempotencyKey: nextKey() });
    const execution = await asPrincipal("agent:connector").execute(
      OP.dispatchMigration,
      { request: request.id, allowance: ALLOWANCE, connector: CONNECTOR_DATABASE },
      { idempotencyKey: nextKey() },
    ) as { id: string };
    const connector = new PostgreSqlMigrationConnector({ pool: targetPool, migrationsDirectory: root, statementTimeoutMs: 2_000, lockTimeoutMs: 2_000 });
    await worker(new Map([[CONNECTOR_DATABASE, connector]])).runOnce();
    expect((await targetPool.query("SELECT count(*)::int AS count FROM public.widget")).rows[0]?.count).toBe(1);
    const replayClaim: ExecutionClaim = {
      executionId: "00000000-0000-4000-8000-000000000088",
      claimToken: "00000000-0000-4000-8000-000000000089",
      attemptCount: 1,
      requestKind: "SCHEMA_MIGRATION",
      connectorId: CONNECTOR_DATABASE,
      connectorKind: "POSTGRESQL",
      payload: { environmentId: ENV_DATABASE, migrationName, migrationSha },
      correlationId: "corr-migration",
    };
    expect(await connector.execute(replayClaim, activeSignal)).toContain(`execution=${execution.id}`);
    expect((await targetPool.query("SELECT count(*)::int AS count FROM public.widget")).rows[0]?.count).toBe(1);
    const changedSql = `${migrationSql}SELECT 2;\n`;
    await writeFile(join(root, `${migrationName}.sql`), changedSql);
    const conflicting = { ...replayClaim, payload: { ...replayClaim.payload, migrationSha: createHash("sha256").update(changedSql).digest("hex") } };
    await expect(connector.execute(conflicting, activeSignal)).rejects.toMatchObject({ code: "MIGRATION_LEDGER_CONFLICT", retryable: false });
  });

  it("rechecks connector authorization before dispatch and immediately before effects", async () => {
    const request = await pi().execute(
      OP.requestIssue,
      { delegation: DELEGATION_ISSUE, repository: REPOSITORY, connector: CONNECTOR_GITHUB, title: "Revoked", body: "No effect" },
      { idempotencyKey: nextKey() },
    ) as { id: string };
    ownerSql(`UPDATE model_signalbox.connector SET status='REVOKED' WHERE id='${CONNECTOR_GITHUB}';`);
    await expect(asPrincipal("agent:connector").execute(
      OP.dispatchIssue,
      { request: request.id, allowance: ALLOWANCE, connector: CONNECTOR_GITHUB },
      { idempotencyKey: nextKey() },
    )).rejects.toBeInstanceOf(PreconditionError);

    ownerSql(`UPDATE model_signalbox.connector SET status='ACTIVE' WHERE id='${CONNECTOR_GITHUB}';`);
    const execution = await asPrincipal("agent:connector").execute(
      OP.dispatchIssue,
      { request: request.id, allowance: ALLOWANCE, connector: CONNECTOR_GITHUB },
      { idempotencyKey: nextKey() },
    ) as { id: string };
    ownerSql(`UPDATE model_signalbox.connector SET status='REVOKED' WHERE id='${CONNECTOR_GITHUB}';`);
    expect(await worker(new Map([[CONNECTOR_GITHUB, githubConnector()]])).runOnce()).toBe(false);
    expect(githubPosts).toBe(0);
    expect(ownerSql(`SELECT status FROM model_signalbox.execution WHERE id='${execution.id}';`)).toBe("PENDING");
  });

  it("bounds timeout retries and records only a sanitized terminal code", async () => {
    const { executionId } = await dispatchIssue();
    const timingOut: ExecutionConnector = {
      kind: "GITHUB",
      async execute(_claim, signal) {
        await new Promise<void>((_resolve, reject) => signal.addEventListener("abort", () => reject(new ConnectorFailure("secret host:5432", true)), { once: true }));
        return "unreachable";
      },
      async recover() { return undefined; },
    };
    const runner = worker(new Map([[CONNECTOR_GITHUB, timingOut]]), "worker-timeout", { connectorTimeoutMs: 100, maxAttempts: 1 });
    await runner.runOnce();
    ownerSql(`UPDATE model_signalbox_worker.execution_claim SET leased_until=now(), next_attempt_at=now() WHERE execution_id='${executionId}';`);
    await runner.runOnce();
    expect(ownerSql(`SELECT status || ':' || failure_message FROM model_signalbox.execution WHERE id='${executionId}';`)).toBe("FAILED:RETRY_EXHAUSTED");
  });
});
