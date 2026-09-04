// Issues a scoped Signalbox access token for the seeded demo agent.
//
// Prints the token once. Signalbox stores only its SHA-256 hash, so a lost
// token cannot be recovered; re-run to issue another, or rotate through
// POST /auth/agent-tokens/:id/rotate.
//
// Requires seed.sql to have been applied, and DATABASE_URL to name a login
// role that is a member of modellang_gateway (the same role the server uses).
//
// Signalbox enforces its own rule here: model_signalbox_auth.can_manage_agent
// only permits an ACTIVE HUMAN in the agent's organization who either holds
// ADMIN or is that agent's accountable owner. The seeded Ops Admin holds
// ADMIN, so it is the caller below.
//
//   DATABASE_URL=... node scripts/demo-token.mjs [--label demo] [--expires 2027-01-31]

import { createHash, randomBytes } from "node:crypto";
import pg from "pg";

const SEEDED_AGENT = "00000000-0000-4000-8000-0000000000b1";
const SEEDED_ADMIN_ISSUER = "https://signalbox.test";
const SEEDED_ADMIN_SUBJECT = "human:opsadmin";

function argument(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return fallback;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`--${name} requires a value`);
  return value;
}

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const label = argument("label", "demo");
const expiresRaw = argument("expires", "2027-01-31");
const expiresAt = new Date(`${expiresRaw}T00:00:00Z`);
if (Number.isNaN(expiresAt.getTime())) throw new Error(`--expires must be a date, received '${expiresRaw}'`);
if (expiresAt <= new Date()) throw new Error("--expires must be in the future");

const agentId = argument("agent", SEEDED_AGENT);
const tokenIssuer = process.env.AGENT_TOKEN_ISSUER
  ?? new URL("/auth/agent-tokens", process.env.PUBLIC_ORIGIN ?? "http://127.0.0.1:4310").href;

const secret = randomBytes(32).toString("base64url");
const secretHash = `sha256:${createHash("sha256").update(secret, "utf8").digest("hex")}`;

const pool = new pg.Pool({ connectionString: databaseUrl });
try {
  const result = await pool.query(
    "SELECT * FROM model_signalbox_auth.issue_agent_token($1, $2, $3, $4, $5, $6, $7)",
    [SEEDED_ADMIN_ISSUER, SEEDED_ADMIN_SUBJECT, agentId, label, secretHash, expiresAt, tokenIssuer],
  );
  const row = result.rows[0];
  if (!row) throw new Error("Token issuance returned no credential");

  process.stdout.write(`${JSON.stringify({
    credentialId: row.credential_id,
    orgId: row.credential_org_id,
    agentId: row.credential_agent_id,
    label: row.credential_label,
    expiresAt: row.credential_expires_at,
    issuer: tokenIssuer,
    token: `sbx_${row.credential_id}.${secret}`,
  }, null, 2)}\n`);
} finally {
  await pool.end();
}
