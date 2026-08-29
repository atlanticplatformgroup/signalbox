// Signalbox complete-domain enforcement guarantees against real PostgreSQL 16.
// Every operation crosses the generated, caller-bound gateway. Nothing is mocked.
import { execFileSync } from "node:child_process";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import pg from "pg";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import {
  AuthorizationError,
  IdempotencyConflictError,
  InvariantError,
  PreconditionError,
} from "../generated/signalbox/dist/errors.js";

const ISSUER = "https://signalbox.test";
const ORG_ACME = "00000000-0000-4000-8000-0000000000a1";
const AGENT_PI = "00000000-0000-4000-8000-0000000000b1";
const REPOSITORY = "00000000-0000-4000-8000-0000000000d1";
const OTHER_REPOSITORY = "00000000-0000-4000-8000-0000000000d9";
const ENV_PROD = "00000000-0000-4000-8000-0000000000e1";
const ENV_STAGING = "00000000-0000-4000-8000-0000000000e2";
const ENV_DATABASE = "00000000-0000-4000-8000-0000000000e3";
const CONNECTOR_GITHUB = "00000000-0000-4000-8000-0000000000c1";
const CONNECTOR_DEPLOY = "00000000-0000-4000-8000-0000000000c2";
const CONNECTOR_DATABASE = "00000000-0000-4000-8000-0000000000c3";
const CONNECTOR_OTHER = "00000000-0000-4000-8000-0000000000c9";
const DELEGATION_ISSUE = "00000000-0000-4000-8000-0000000000f1";
const DELEGATION_PULL = "00000000-0000-4000-8000-0000000000f2";
const DELEGATION_STAGING = "00000000-0000-4000-8000-0000000000f3";
const DELEGATION_PROD = "00000000-0000-4000-8000-0000000000f4";
const DELEGATION_MIGRATION = "00000000-0000-4000-8000-0000000000f5";
const ALLOWANCES = [
  "00000000-0000-4000-8000-000000000101",
  "00000000-0000-4000-8000-000000000102",
  "00000000-0000-4000-8000-000000000103",
  "00000000-0000-4000-8000-000000000104",
  "00000000-0000-4000-8000-000000000105",
  "00000000-0000-4000-8000-000000000106",
] as const;

const OP = {
  requestIssue: "action:act_ea693a4d658449fbab5741b8369bc276",
  requestPull: "action:act_c4bb8af190dd48efb9784efb9ff9030c",
  requestStaging: "action:act_1388eb9f38684fa0830f60156cdba497",
  requestProduction: "action:act_d10d1618ed4045f396b64fc3745ce3dd",
  requestMigration: "action:act_411bfff32560406186bd2d442f1ecf3b",
  approveProduction: "action:act_047a601f15384b5ea4bfa05b5ef72676",
  rejectProduction: "action:act_18ab026d358144dfa4d1729e40dd832e",
  approveMigration: "action:act_4c170dfcb0224cb8aaf078fe6b6ef23d",
  rejectMigration: "action:act_d3a1935e42f24e4d84d25bc05ee690ad",
  dispatchIssue: "action:act_cbb72fd307704ab3927aa4bea8112fbf",
  dispatchPull: "action:act_3e99da927be642efac3d1bee026ef00a",
  dispatchStaging: "action:act_3e26a4d454634bf3a2058204146d7c45",
  dispatchProduction: "action:act_4a9421bfc2e744969b9f73109e6cda54",
  dispatchMigration: "action:act_70d3862584094631aca61e9db664d991",
  completeExecution: "action:act_5be24324b68d4c2eb334732b36e1b16c",
  failExecution: "action:act_926686163a6544e79d44dea9336d2c88",
  myIssues: "query:qry_22f082ad9148490eb301e04fdc6e2ce3",
  myPulls: "query:qry_a96d198b028c45f2b0ec43471cb5ba09",
  myDeployments: "query:qry_60d1c5d416eb428caa385db274edcb4b",
  deploymentInbox: "query:qry_21f24f72d72c4bb98df539477f0e81f2",
  myMigrations: "query:qry_e3c9ea88ab664e96a5eaf20efc8c94a9",
  migrationInbox: "query:qry_8a136078ed3b4ee6893410b631ac5a04",
  myExecutions: "query:qry_e608c643d17c4a908f26e6a538630a51",
} as const;

const pool = new pg.Pool({
  host: "127.0.0.1",
  port: 55433,
  database: "sb_managed",
  user: "sb_gateway_login",
  password: "gw",
  max: 8,
});

const as = (subject: string) =>
  createSignalboxGatewayExecutor(pool as never, { issuer: ISSUER, subject });

const pi = as("agent:pi");
const connectorWorker = as("agent:connector");
const dana = as("human:dana");
const raj = as("human:raj");
const opsAdmin = as("human:opsadmin");
const outsider = as("human:outsider");

let n = 0;
const key = () => `domain-${Date.now()}-${n++}`;

function sql(statement: string): string {
  return execFileSync(
    "docker",
    [
      "exec",
      "-i",
      "sb-pg16",
      "psql",
      "-U",
      "nebius_admin",
      "-d",
      "sb_managed",
      "-tAq",
      "-v",
      "ON_ERROR_STOP=1",
      "-f",
      "-",
    ],
    { input: `SET ROLE modellang_owner;\n${statement}`, encoding: "utf8" },
  ).trim();
}

function reseed(): void {
  sql(`
    TRUNCATE
      model_signalbox_internal.action_effect_audit,
      model_signalbox_internal.action_audit,
      model_signalbox_internal.command_receipt,
      model_signalbox_internal.event_outbox,
      model_signalbox_internal.query_audit,
      model_signalbox.execution,
      model_signalbox.approval,
      model_signalbox.schema_migration_request,
      model_signalbox.deployment_request,
      model_signalbox.pull_request,
      model_signalbox.issue_request
    CASCADE;
    UPDATE model_signalbox.principal SET status='ACTIVE';
    UPDATE model_signalbox.principal SET roles='{MEMBER,APPROVER}' WHERE id IN (
      '00000000-0000-4000-8000-0000000000b2',
      '00000000-0000-4000-8000-0000000000b3'
    );
    UPDATE model_signalbox.delegation SET status='ACTIVE';
    UPDATE model_signalbox.connector SET status='ACTIVE';
    UPDATE model_signalbox.allowance
      SET org_id='00000000-0000-4000-8000-0000000000a1',
          agent_id='00000000-0000-4000-8000-0000000000b1'
      WHERE id IN (
        '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000103',
        '00000000-0000-4000-8000-000000000104',
        '00000000-0000-4000-8000-000000000105',
        '00000000-0000-4000-8000-000000000106'
      );
  `);
}

async function requestIssue(title = "Investigate flaky build"): Promise<string> {
  const created = (await pi.execute(
    OP.requestIssue,
    {
      delegation: DELEGATION_ISSUE,
      repository: REPOSITORY,
      connector: CONNECTOR_GITHUB,
      title,
      body: "The release build failed twice.",
    },
    { idempotencyKey: key() },
  )) as { id: string; status: string };
  expect(created.status).toBe("READY");
  return created.id;
}

async function requestProduction(commitSha = "a".repeat(40)): Promise<string> {
  const created = (await pi.execute(
    OP.requestProduction,
    {
      delegation: DELEGATION_PROD,
      environment: ENV_PROD,
      connector: CONNECTOR_DEPLOY,
      commitSha,
    },
    { idempotencyKey: key() },
  )) as { id: string; status: string };
  expect(created.status).toBe("PENDING_APPROVAL");
  return created.id;
}

async function requestMigration(name = "add_audit_index"): Promise<string> {
  const created = (await pi.execute(
    OP.requestMigration,
    {
      delegation: DELEGATION_MIGRATION,
      environment: ENV_DATABASE,
      connector: CONNECTOR_DATABASE,
      migrationName: name,
      migrationSha: "b".repeat(64),
    },
    { idempotencyKey: key() },
  )) as { id: string; status: string };
  expect(created.status).toBe("PENDING_APPROVAL");
  return created.id;
}

afterAll(async () => {
  await pool.end();
});

beforeEach(() => {
  reseed();
});

describe("caller identity and agent lifecycle", () => {
  it("derives the requester from verified caller context", async () => {
    const created = (await pi.execute(
      OP.requestIssue,
      {
        delegation: DELEGATION_ISSUE,
        repository: REPOSITORY,
        connector: CONNECTOR_GITHUB,
        title: "Bound identity",
        body: "No caller id appears in this input.",
      },
      { idempotencyKey: key() },
    )) as { requestedBy: string; org: string };

    expect(created.requestedBy).toBe(AGENT_PI);
    expect(created.org).toBe(ORG_ACME);
  });

  it("rejects an unbound credential", async () => {
    await expect(
      as("agent:not-registered").execute(
        OP.requestIssue,
        {
          delegation: DELEGATION_ISSUE,
          repository: REPOSITORY,
          connector: CONNECTOR_GITHUB,
          title: "No identity",
          body: "Rejected",
        },
        { idempotencyKey: key() },
      ),
    ).rejects.toThrow();
  });

  it("rejects a revoked agent before creating a request", async () => {
    sql(`UPDATE model_signalbox.principal SET status='REVOKED' WHERE id='${AGENT_PI}';`);
    await expect(requestIssue()).rejects.toBeInstanceOf(AuthorizationError);
    expect(sql("SELECT count(*) FROM model_signalbox.issue_request;")).toBe("0");
  });
});

describe("delegation and resource scope", () => {
  it("rejects a capability-mismatched delegation", async () => {
    await expect(
      pi.execute(
        OP.requestIssue,
        {
          delegation: DELEGATION_PULL,
          repository: REPOSITORY,
          connector: CONNECTOR_GITHUB,
          title: "Wrong capability",
          body: "Rejected",
        },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(AuthorizationError);
  });

  it("rejects a revoked delegation", async () => {
    sql(`UPDATE model_signalbox.delegation SET status='REVOKED' WHERE id='${DELEGATION_ISSUE}';`);
    await expect(requestIssue()).rejects.toBeInstanceOf(AuthorizationError);
  });

  it("rejects cross-tenant repository and connector inputs", async () => {
    await expect(
      pi.execute(
        OP.requestIssue,
        {
          delegation: DELEGATION_ISSUE,
          repository: OTHER_REPOSITORY,
          connector: CONNECTOR_OTHER,
          title: "Cross tenant",
          body: "Rejected",
        },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(AuthorizationError);
  });
});

describe("directly delegated operations", () => {
  it("creates, dispatches, and completes an issue request", async () => {
    const request = await requestIssue();
    const execution = (await connectorWorker.execute(
      OP.dispatchIssue,
      { request, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    )) as { id: string; status: string; requestKind: string };

    expect(execution.status).toBe("PENDING");
    expect(execution.requestKind).toBe("ISSUE");

    const completed = (await connectorWorker.execute(
      OP.completeExecution,
      { execution: execution.id, externalReference: "https://github.com/acme/web/issues/1" },
      { idempotencyKey: key() },
    )) as { status: string; externalReference: string };
    expect(completed).toMatchObject({
      status: "SUCCEEDED",
      externalReference: "https://github.com/acme/web/issues/1",
    });
  });

  it("creates, dispatches, and records failure for a pull request", async () => {
    const request = (await pi.execute(
      OP.requestPull,
      {
        delegation: DELEGATION_PULL,
        repository: REPOSITORY,
        connector: CONNECTOR_GITHUB,
        headBranch: "agent/fix",
        baseBranch: "main",
        title: "Fix release",
      },
      { idempotencyKey: key() },
    )) as { id: string; status: string };
    expect(request.status).toBe("READY");

    const execution = (await connectorWorker.execute(
      OP.dispatchPull,
      { request: request.id, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    )) as { id: string };
    const failed = (await connectorWorker.execute(
      OP.failExecution,
      { execution: execution.id, failureMessage: "branch protection rejected the push" },
      { idempotencyKey: key() },
    )) as { status: string; failureMessage: string };

    expect(failed).toMatchObject({
      status: "FAILED",
      failureMessage: "branch protection rejected the push",
    });
  });

  it("dispatches staging without human approval", async () => {
    const request = (await pi.execute(
      OP.requestStaging,
      {
        delegation: DELEGATION_STAGING,
        environment: ENV_STAGING,
        connector: CONNECTOR_DEPLOY,
        commitSha: "c".repeat(40),
      },
      { idempotencyKey: key() },
    )) as { id: string; status: string; environmentTier: string };
    expect(request).toMatchObject({ status: "READY", environmentTier: "STAGING" });

    await connectorWorker.execute(
      OP.dispatchStaging,
      { request: request.id, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    );
    expect(
      sql(`SELECT status FROM model_signalbox.deployment_request WHERE id='${request.id}';`),
    ).toBe("DISPATCHED");
  });
});

describe("production approval and separation of duties", () => {
  it("creates production requests pending approval", async () => {
    const request = await requestProduction();
    const inbox = (await dana.execute(OP.deploymentInbox, {})) as { items: unknown[] };
    expect(inbox.items).toHaveLength(1);
    expect(
      sql(`SELECT status FROM model_signalbox.deployment_request WHERE id='${request}';`),
    ).toBe("PENDING_APPROVAL");
  });

  it("rejects self-approval and enforces it at rest", async () => {
    const request = await requestProduction();
    await expect(
      pi.execute(OP.approveProduction, { request }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(AuthorizationError);

    expect(() =>
      sql(`UPDATE model_signalbox.deployment_request
           SET status='APPROVED', approved_by_id=requested_by_id, approved_by_roles='{APPROVER}'
           WHERE id='${request}';`),
    ).toThrow(/approver_differs_from_requester|violates check constraint/i);
  });

  it("rejects cross-tenant and unauthorized human approvers", async () => {
    const request = await requestProduction();
    await expect(
      outsider.execute(OP.approveProduction, { request }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(AuthorizationError);

    sql(`UPDATE model_signalbox.principal SET roles='{MEMBER}' WHERE id='00000000-0000-4000-8000-0000000000b2';`);
    await expect(
      dana.execute(OP.approveProduction, { request }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(AuthorizationError);
  });

  it("requires approval before dispatch and admits it afterward", async () => {
    const request = await requestProduction();
    await expect(
      connectorWorker.execute(
        OP.dispatchProduction,
        { request, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(PreconditionError);

    const approval = (await dana.execute(
      OP.approveProduction,
      { request },
      { idempotencyKey: key() },
    )) as { requestId: string; requestKind: string; approver: string };
    expect(approval).toMatchObject({ requestId: request, requestKind: "DEPLOYMENT" });

    await connectorWorker.execute(
      OP.dispatchProduction,
      { request, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    );
    expect(
      sql(`SELECT status FROM model_signalbox.deployment_request WHERE id='${request}';`),
    ).toBe("DISPATCHED");
  });

  it("prevents dispatch after rejection", async () => {
    const request = await requestProduction();
    await dana.execute(OP.rejectProduction, { request }, { idempotencyKey: key() });
    await expect(
      connectorWorker.execute(
        OP.dispatchProduction,
        { request, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(PreconditionError);
  });
});

describe("schema migration governance", () => {
  it("requires independent approval before dispatching a migration", async () => {
    const request = await requestMigration();
    const inbox = (await dana.execute(OP.migrationInbox, {})) as { items: unknown[] };
    expect(inbox.items).toHaveLength(1);

    await expect(
      connectorWorker.execute(
        OP.dispatchMigration,
        { request, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(PreconditionError);

    const approval = (await dana.execute(
      OP.approveMigration,
      { request },
      { idempotencyKey: key() },
    )) as { requestKind: string };
    expect(approval.requestKind).toBe("SCHEMA_MIGRATION");

    await connectorWorker.execute(
      OP.dispatchMigration,
      { request, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    );
    expect(
      sql(`SELECT status FROM model_signalbox.schema_migration_request WHERE id='${request}';`),
    ).toBe("DISPATCHED");
  });

  it("rejects migration self-approval and rejected migration dispatch", async () => {
    const request = await requestMigration();
    await expect(
      pi.execute(OP.approveMigration, { request }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(AuthorizationError);
    await dana.execute(OP.rejectMigration, { request }, { idempotencyKey: key() });
    await expect(
      connectorWorker.execute(
        OP.dispatchMigration,
        { request, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(PreconditionError);
  });
});

describe("exactly-once dispatch and allowance consumption", () => {
  it("dispatches one request at most once", async () => {
    const request = await requestIssue();
    await connectorWorker.execute(
      OP.dispatchIssue,
      { request, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    );
    await expect(
      connectorWorker.execute(
        OP.dispatchIssue,
        { request, allowance: ALLOWANCES[1] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(PreconditionError);
    expect(sql(`SELECT count(*) FROM model_signalbox.execution WHERE request_id='${request}';`)).toBe(
      "1",
    );
  });

  it("cannot spend one allowance on two requests", async () => {
    const first = await requestIssue("First");
    const second = await requestIssue("Second");
    await connectorWorker.execute(
      OP.dispatchIssue,
      { request: first, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    );
    await expect(
      connectorWorker.execute(
        OP.dispatchIssue,
        { request: second, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(InvariantError);
    expect(sql("SELECT count(*) FROM model_signalbox.execution;")).toBe("1");
    expect(sql(`SELECT status FROM model_signalbox.issue_request WHERE id='${second}';`)).toBe(
      "READY",
    );
  });

  it("rejects an allowance owned by another principal", async () => {
    const request = await requestIssue();
    sql(`UPDATE model_signalbox.allowance SET agent_id='00000000-0000-4000-8000-0000000000b6' WHERE id='${ALLOWANCES[0]}';`);
    await expect(
      connectorWorker.execute(
        OP.dispatchIssue,
        { request, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(PreconditionError);
  });
});

describe("idempotency", () => {
  it("replays the stored result without creating a duplicate", async () => {
    const idempotencyKey = key();
    const input = {
      delegation: DELEGATION_ISSUE,
      repository: REPOSITORY,
      connector: CONNECTOR_GITHUB,
      title: "Replay",
      body: "Same input",
    };
    const first = (await pi.execute(OP.requestIssue, input, { idempotencyKey })) as { id: string };
    const replay = (await pi.execute(OP.requestIssue, input, { idempotencyKey })) as { id: string };
    expect(replay.id).toBe(first.id);
    expect(sql("SELECT count(*) FROM model_signalbox.issue_request;")).toBe("1");
  });

  it("rejects the same key with different input", async () => {
    const idempotencyKey = key();
    const input = {
      delegation: DELEGATION_ISSUE,
      repository: REPOSITORY,
      connector: CONNECTOR_GITHUB,
      title: "Original",
      body: "Same body",
    };
    await pi.execute(OP.requestIssue, input, { idempotencyKey });
    await expect(
      pi.execute(OP.requestIssue, { ...input, title: "Changed" }, { idempotencyKey }),
    ).rejects.toBeInstanceOf(IdempotencyConflictError);
  });

  it("scopes idempotency keys to the authenticated principal", async () => {
    const request = await requestProduction();
    const idempotencyKey = key();
    await dana.execute(OP.approveProduction, { request }, { idempotencyKey });
    await expect(
      raj.execute(OP.approveProduction, { request }, { idempotencyKey }),
    ).rejects.toBeInstanceOf(PreconditionError);
  });
});

describe("concurrency", () => {
  it("admits exactly one of two racing approvers", async () => {
    const request = await requestProduction();
    const results = await Promise.allSettled([
      dana.execute(OP.approveProduction, { request }, { idempotencyKey: key() }),
      raj.execute(OP.approveProduction, { request }, { idempotencyKey: key() }),
    ]);
    expect(results.filter(({ status }) => status === "fulfilled")).toHaveLength(1);
    expect(sql(`SELECT count(*) FROM model_signalbox.approval WHERE request_id='${request}';`)).toBe(
      "1",
    );
  });

  it("admits exactly one of two dispatches racing the same allowance", async () => {
    const first = await requestIssue("Race one");
    const second = await requestIssue("Race two");
    const results = await Promise.allSettled([
      connectorWorker.execute(
        OP.dispatchIssue,
        { request: first, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
      connectorWorker.execute(
        OP.dispatchIssue,
        { request: second, allowance: ALLOWANCES[0] },
        { idempotencyKey: key() },
      ),
    ]);
    expect(results.filter(({ status }) => status === "fulfilled")).toHaveLength(1);
    expect(sql("SELECT count(*) FROM model_signalbox.execution;")).toBe("1");
  });
});

describe("tenant-scoped queries", () => {
  it("confines every request and execution history to the caller organization", async () => {
    const issue = await requestIssue();
    await requestProduction();
    await requestMigration();
    await connectorWorker.execute(
      OP.dispatchIssue,
      { request: issue, allowance: ALLOWANCES[0] },
      { idempotencyKey: key() },
    );

    for (const operation of [OP.myIssues, OP.myDeployments, OP.myMigrations, OP.myExecutions]) {
      const mine = (await dana.execute(operation, {})) as { items: unknown[] };
      const theirs = (await outsider.execute(operation, {})) as { items: unknown[] };
      expect(mine.items.length, operation).toBeGreaterThan(0);
      expect(theirs.items, operation).toHaveLength(0);
    }

    const pulls = (await dana.execute(OP.myPulls, {})) as { items: unknown[] };
    expect(pulls.items).toHaveLength(0);
  });
});

describe("audit provenance", () => {
  it("stamps every decision with model version and source hash", async () => {
    const request = await requestProduction();
    await dana.execute(OP.approveProduction, { request }, { idempotencyKey: key() });

    const stamped = Number(
      sql(`SELECT count(*) FROM model_signalbox_internal.action_audit
           WHERE decision_outcome='executed'
             AND model_id='model:Signalbox'
             AND model_version='0.51.0'
             AND source_hash LIKE 'sha256:%'
             AND decision_evidence->'model'->>'version'='0.51.0'
             AND decision_evidence->'model'->>'sourceHash'=source_hash;`),
    );
    expect(stamped).toBeGreaterThanOrEqual(2);
  });
});
