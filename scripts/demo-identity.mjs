// Binds a GitHub account to a demo HUMAN principal so it can open the
// Governance Studio.
//
// Signalbox verifies a human bearer against GitHub or an OIDC issuer and then
// resolves it through an owner-controlled binding. Authentication alone grants
// nothing: without the binding below, a valid GitHub token still fails with
// SB_UNAUTHENTICATED.
//
// The demo principal is given MEMBER and APPROVER so a reviewer can approve a
// pending governed action and watch the agent proceed. It is deliberately not
// given ADMIN, which would allow it to mint agent credentials.
//
// Writing to model_signalbox.principal requires the owner role, so this needs
// an administrative connection string rather than the application one.
//
//   ADMIN_DATABASE_URL=... node scripts/demo-identity.mjs --github-id 12345678
//
// Find the numeric id for an account with:
//
//   gh api users/<login> --jq .id
//
// Re-running is safe. An existing binding is left untouched.

import pg from "pg";

function argument(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) {
    if (fallback === undefined) throw new Error(`--${name} is required`);
    return fallback;
  }
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`--${name} requires a value`);
  return value;
}

const databaseUrl = process.env.ADMIN_DATABASE_URL;
if (!databaseUrl) throw new Error("ADMIN_DATABASE_URL is required (owner or superuser connection)");

// Either bind a GitHub account by numeric id, or bind an arbitrary
// issuer/subject pair for an OIDC identity.
//
//   --github-id 12345678
//   --issuer https://demo.example.com --subject demo-reviewer
const explicitIssuer = argument("issuer", "");
const explicitSubject = argument("subject", "");

let issuer;
let subject;
if (explicitIssuer || explicitSubject) {
  if (!explicitIssuer || !explicitSubject) throw new Error("--issuer and --subject must be given together");
  issuer = explicitIssuer;
  subject = explicitSubject;
} else {
  const githubId = argument("github-id");
  if (!/^[1-9][0-9]*$/.test(githubId)) throw new Error(`--github-id must be a positive integer, received '${githubId}'`);
  issuer = "https://github.com";
  subject = `github:user:${githubId}`;
}

const displayName = argument("name", "Demo Reviewer");
const orgSlug = argument("org", "acme");

const pool = new pg.Pool({ connectionString: databaseUrl });
const client = await pool.connect();
try {
  await client.query("BEGIN");
  await client.query("SET ROLE modellang_owner");

  const existing = await client.query(
    `SELECT p.id, p.display_name, p.kind, p.status, p.roles
     FROM model_signalbox_internal.gateway_principal_binding AS b
     JOIN model_signalbox.principal AS p ON p.id = b.principal_id
     WHERE b.issuer = $1 AND b.subject = $2`,
    [issuer, subject],
  );

  if (existing.rowCount > 0) {
    const row = existing.rows[0];
    await client.query("COMMIT");
    process.stdout.write(`${JSON.stringify({
      action: "unchanged",
      subject,
      principalId: row.id,
      displayName: row.display_name,
      kind: row.kind,
      status: row.status,
      roles: row.roles,
    }, null, 2)}\n`);
  } else {
    const created = await client.query(
      `WITH created AS (
         INSERT INTO model_signalbox.principal
           (org_id, kind, display_name, status, roles, responsible_owner_id)
         SELECT id, 'HUMAN', $1, 'ACTIVE', '{MEMBER,APPROVER}', NULL
         FROM model_signalbox.organization
         WHERE slug = $2
         RETURNING id, org_id
       )
       INSERT INTO model_signalbox_internal.gateway_principal_binding
         (issuer, subject, principal_id)
       SELECT $3, $4, id FROM created
       RETURNING principal_id`,
      [displayName, orgSlug, issuer, subject],
    );
    if (created.rowCount !== 1) throw new Error(`Organization '${orgSlug}' was not found`);
    await client.query("COMMIT");
    process.stdout.write(`${JSON.stringify({
      action: "created",
      subject,
      principalId: created.rows[0].principal_id,
      displayName,
      roles: ["MEMBER", "APPROVER"],
    }, null, 2)}\n`);
  }
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
  await pool.end();
}
