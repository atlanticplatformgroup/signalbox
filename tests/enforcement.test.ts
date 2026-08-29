// Signalbox spike — enforcement guarantees, exercised against real PostgreSQL 16
// through the ModelLang-generated gateway. Nothing here is mocked.
import { execFileSync } from "node:child_process";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import pg from "pg";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import {
  AuthorizationError,
  InvariantError,
  IdempotencyConflictError,
  PreconditionError,
} from "../generated/signalbox/dist/errors.js";

const ISSUER = "https://signalbox.test";
const ORG_ACME = "00000000-0000-0000-0000-0000000000a1";
const ENV_PROD = "00000000-0000-0000-0000-0000000000c1";
const ENV_STAGING = "00000000-0000-0000-0000-0000000000c2";
const DELEGATION = "00000000-0000-0000-0000-0000000000d1";
const ALLOWANCE_1 = "00000000-0000-0000-0000-0000000000e1";
const ALLOWANCE_2 = "00000000-0000-0000-0000-0000000000e2";
const AGENT_PI = "00000000-0000-0000-0000-0000000000b1";

const OP = {
  request: "action:act_d10d1618ed4045f396b64fc3745ce3dd",
  approve: "action:act_047a601f15384b5ea4bfa05b5ef72676",
  execute: "action:act_4a9421bfc2e744969b9f73109e6cda54",
  reject: "action:act_18ab026d358144dfa4d1729e40dd832e",
  myRequests: "query:qry_60d1c5d416eb428caa385db274edcb4b",
} as const;

const pool = new pg.Pool({
  host: "127.0.0.1",
  port: 55433,
  database: "sb_managed",
  user: "sb_gateway_login",
  password: "gw",
  max: 8,
});

/** The host verifies a credential, then hands the gateway a verified principal. */
const as = (subject: string) =>
  createSignalboxGatewayExecutor(pool as never, { issuer: ISSUER, subject });

const pi = as("agent:pi");
const dana = as("human:dana");
const raj = as("human:raj");
const opsAdmin = as("human:opsadmin");
const outsider = as("human:outsider");

let n = 0;
const key = () => `spike-${Date.now()}-${n++}`;

function reseed(): void {
  execFileSync(
    "docker",
    ["exec", "-i", "sb-pg16", "psql", "-U", "nebius_admin", "-d", "sb_managed", "-q", "-v", "ON_ERROR_STOP=1", "-f", "-"],
    { input: SEED, stdio: ["pipe", "ignore", "pipe"] },
  );
}

/** Direct privileged SQL, used only to probe at-rest constraints. */
function sql(statement: string): string {
  return execFileSync(
    "docker",
    ["exec", "-i", "sb-pg16", "psql", "-U", "nebius_admin", "-d", "sb_managed", "-tAq", "-v", "ON_ERROR_STOP=1", "-f", "-"],
    { input: `SET ROLE modellang_owner;\n${statement}`, encoding: "utf8" },
  ).trim();
}

const SEED = `
SET ROLE modellang_owner;
-- action_audit and command_receipt reference each other, so no DELETE order
-- resolves. A single multi-table TRUNCATE breaks the cycle.
TRUNCATE
  model_signalbox_internal.action_effect_audit,
  model_signalbox_internal.action_audit,
  model_signalbox_internal.command_receipt,
  model_signalbox_internal.event_outbox,
  model_signalbox_internal.query_audit,
  model_signalbox.execution,
  model_signalbox.approval,
  model_signalbox.production_deploy_request
CASCADE;
RESET ROLE;
`;

async function openRequest(commitSha = "a".repeat(40)): Promise<string> {
  const created = (await pi.execute(
    OP.request,
    { delegation: DELEGATION, environment: ENV_PROD, commitSha },
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

describe("caller identity", () => {
  it("is bound by the host and absent from the action input contract", async () => {
    const created = (await pi.execute(
      OP.request,
      { delegation: DELEGATION, environment: ENV_PROD, commitSha: "b".repeat(40) },
      { idempotencyKey: key() },
    )) as { requestedBy: string; org: string };
    // The agent never supplied a principal id; the boundary derived it.
    expect(created.requestedBy).toBe(AGENT_PI);
    expect(created.org).toBe(ORG_ACME);
  });

  it("rejects an unbound credential", async () => {
    await expect(
      as("agent:not-registered").execute(
        OP.request,
        { delegation: DELEGATION, environment: ENV_PROD, commitSha: "c".repeat(40) },
        { idempotencyKey: key() },
      ),
    ).rejects.toThrow();
  });
});

describe("delegation scope", () => {
  it("refuses an environment the delegation does not cover", async () => {
    await expect(
      pi.execute(
        OP.request,
        { delegation: DELEGATION, environment: ENV_STAGING, commitSha: "d".repeat(40) },
        { idempotencyKey: key() },
      ),
    ).rejects.toBeInstanceOf(AuthorizationError);
  });

  it("refuses a revoked delegation", async () => {
    sql(`UPDATE model_signalbox.delegation SET status='REVOKED' WHERE id='${DELEGATION}';`);
    try {
      await expect(
        pi.execute(
          OP.request,
          { delegation: DELEGATION, environment: ENV_PROD, commitSha: "e".repeat(40) },
          { idempotencyKey: key() },
        ),
      ).rejects.toBeInstanceOf(AuthorizationError);
    } finally {
      sql(`UPDATE model_signalbox.delegation SET status='ACTIVE' WHERE id='${DELEGATION}';`);
    }
  });
});

describe("guarantee A — separation of duties", () => {
  it("denies the requesting agent approving its own request", async () => {
    const request = await openRequest();
    await expect(
      pi.execute(OP.approve, { request }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(AuthorizationError);
  });

  it("denies an approver from a different organization", async () => {
    const request = await openRequest();
    await expect(
      outsider.execute(OP.approve, { request }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(AuthorizationError);
  });

  it("denies a human without the APPROVER role", async () => {
    const request = await openRequest();
    sql(`UPDATE model_signalbox.principal SET roles='{MEMBER}' WHERE display_name='Dana Approver';`);
    try {
      await expect(
        dana.execute(OP.approve, { request }, { idempotencyKey: key() }),
      ).rejects.toBeInstanceOf(AuthorizationError);
    } finally {
      sql(`UPDATE model_signalbox.principal SET roles='{MEMBER,APPROVER}' WHERE display_name='Dana Approver';`);
    }
  });

  it("admits an independent human approver", async () => {
    const request = await openRequest();
    await dana.execute(OP.approve, { request }, { idempotencyKey: key() });
    expect(sql(`SELECT status FROM model_signalbox.production_deploy_request WHERE id='${request}';`)).toBe("APPROVED");
    expect(sql(`SELECT count(*) FROM model_signalbox.approval WHERE request_id='${request}';`)).toBe("1");
  });

  it("forbids requester==approver at rest, even for a privileged writer", async () => {
    const request = await openRequest();
    // Bypass the action boundary entirely and attack the table directly.
    expect(() =>
      sql(
        `UPDATE model_signalbox.production_deploy_request
         SET status='APPROVED', approved_by_id=requested_by_id, approved_by_roles='{APPROVER}'
         WHERE id='${request}';`,
      ),
    ).toThrow(/approver_differs_from_requester|violates check constraint/i);
  });
});

describe("guarantee B — a request executes at most once", () => {
  it("refuses a second execution of the same request", async () => {
    const request = await openRequest();
    await dana.execute(OP.approve, { request }, { idempotencyKey: key() });
    await opsAdmin.execute(OP.execute, { request, allowance: ALLOWANCE_1 }, { idempotencyKey: key() });

    await expect(
      opsAdmin.execute(OP.execute, { request, allowance: ALLOWANCE_2 }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(PreconditionError);
    expect(sql(`SELECT count(*) FROM model_signalbox.execution WHERE request_id='${request}';`)).toBe("1");
  });

  it("enforces one-execution-per-request as a storage constraint", async () => {
    const request = await openRequest();
    await dana.execute(OP.approve, { request }, { idempotencyKey: key() });
    await opsAdmin.execute(OP.execute, { request, allowance: ALLOWANCE_1 }, { idempotencyKey: key() });

    expect(() =>
      sql(
        `INSERT INTO model_signalbox.execution (id, org_id, request_id, allowance_id)
         VALUES (gen_random_uuid(), '${ORG_ACME}', '${request}', '${ALLOWANCE_2}');`,
      ),
    ).toThrow(/duplicate key|unique/i);
  });
});

describe("guarantee C — an allowance is consumed at most once", () => {
  it("refuses to spend the same allowance on a second request", async () => {
    const first = await openRequest("1".repeat(40));
    await dana.execute(OP.approve, { request: first }, { idempotencyKey: key() });
    await opsAdmin.execute(OP.execute, { request: first, allowance: ALLOWANCE_1 }, { idempotencyKey: key() });

    const second = await openRequest("2".repeat(40));
    await dana.execute(OP.approve, { request: second }, { idempotencyKey: key() });

    // Same allowance token, different request: must fail on the unique constraint.
    await expect(
      opsAdmin.execute(OP.execute, { request: second, allowance: ALLOWANCE_1 }, { idempotencyKey: key() }),
    ).rejects.toBeInstanceOf(InvariantError);

    expect(sql("SELECT count(*) FROM model_signalbox.execution;")).toBe("1");
    // The rejected request did not transition.
    expect(sql(`SELECT status FROM model_signalbox.production_deploy_request WHERE id='${second}';`)).toBe("APPROVED");
  });

  it("exhausts the budget when every allowance is spent", async () => {
    for (const [i, allowance] of [ALLOWANCE_1, ALLOWANCE_2].entries()) {
      const request = await openRequest(String(i).repeat(40));
      await dana.execute(OP.approve, { request }, { idempotencyKey: key() });
      await opsAdmin.execute(OP.execute, { request, allowance }, { idempotencyKey: key() });
    }
    expect(sql("SELECT count(*) FROM model_signalbox.execution;")).toBe("2");
    // No unconsumed allowance remains for the period.
    expect(
      sql(`SELECT count(*) FROM model_signalbox.allowance a
           WHERE a.period='2026-10'
             AND NOT EXISTS (SELECT 1 FROM model_signalbox.execution e WHERE e.allowance_id=a.id);`),
    ).toBe("0");
  });
});

describe("idempotency", () => {
  it("replays one stored result instead of creating a second request", async () => {
    const k = key();
    const input = { delegation: DELEGATION, environment: ENV_PROD, commitSha: "f".repeat(40) };
    const first = (await pi.execute(OP.request, input, { idempotencyKey: k })) as { id: string };
    const replay = (await pi.execute(OP.request, input, { idempotencyKey: k })) as { id: string };

    expect(replay.id).toBe(first.id);
    expect(sql("SELECT count(*) FROM model_signalbox.production_deploy_request;")).toBe("1");
  });

  it("rejects the same key carrying different input", async () => {
    const k = key();
    await pi.execute(
      OP.request,
      { delegation: DELEGATION, environment: ENV_PROD, commitSha: "0".repeat(40) },
      { idempotencyKey: k },
    );
    await expect(
      pi.execute(
        OP.request,
        { delegation: DELEGATION, environment: ENV_PROD, commitSha: "9".repeat(40) },
        { idempotencyKey: k },
      ),
    ).rejects.toBeInstanceOf(IdempotencyConflictError);
  });

  it("scopes keys per principal", async () => {
    const request = await openRequest();
    const k = key();
    await dana.execute(OP.approve, { request }, { idempotencyKey: k });
    // Raj reusing Dana's key must not replay Dana's stored result.
    await expect(
      raj.execute(OP.approve, { request }, { idempotencyKey: k }),
    ).rejects.toBeInstanceOf(PreconditionError);
  });
});

describe("guarantee D — concurrency", () => {
  it("admits exactly one winner when two approvers race the same request", async () => {
    const request = await openRequest();
    const results = await Promise.allSettled([
      dana.execute(OP.approve, { request }, { idempotencyKey: key() }),
      raj.execute(OP.approve, { request }, { idempotencyKey: key() }),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    expect(fulfilled).toHaveLength(1);
    expect(sql(`SELECT count(*) FROM model_signalbox.approval WHERE request_id='${request}';`)).toBe("1");
    expect(sql(`SELECT status FROM model_signalbox.production_deploy_request WHERE id='${request}';`)).toBe("APPROVED");
  });

  it("admits exactly one winner when two executions race the same allowance", async () => {
    const first = await openRequest("3".repeat(40));
    const second = await openRequest("4".repeat(40));
    await dana.execute(OP.approve, { request: first }, { idempotencyKey: key() });
    await dana.execute(OP.approve, { request: second }, { idempotencyKey: key() });

    const results = await Promise.allSettled([
      opsAdmin.execute(OP.execute, { request: first, allowance: ALLOWANCE_1 }, { idempotencyKey: key() }),
      opsAdmin.execute(OP.execute, { request: second, allowance: ALLOWANCE_1 }, { idempotencyKey: key() }),
    ]);

    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(sql("SELECT count(*) FROM model_signalbox.execution;")).toBe("1");
  });
});

describe("tenant isolation", () => {
  it("confines reads to the caller's organization", async () => {
    await openRequest();
    const mine = (await dana.execute(OP.myRequests, {})) as { items: unknown[] };
    const theirs = (await outsider.execute(OP.myRequests, {})) as { items: unknown[] };

    expect(mine.items.length).toBe(1);
    expect(theirs.items.length).toBe(0);
  });
});

describe("audit", () => {
  it("records a decision with model provenance for every executed action", async () => {
    const request = await openRequest();
    await dana.execute(OP.approve, { request }, { idempotencyKey: key() });

    const rows = sql(
      `SELECT count(*) FROM model_signalbox_internal.action_audit
       WHERE decision_evidence->>'outcome' = 'executed';`,
    );
    expect(Number(rows)).toBeGreaterThanOrEqual(2);

    const stamped = sql(
      `SELECT count(*) FROM model_signalbox_internal.action_audit
       WHERE decision_evidence ? 'model' OR decision_evidence ? 'version';`,
    );
    expect(Number(stamped)).toBeGreaterThanOrEqual(2);
  });
});
