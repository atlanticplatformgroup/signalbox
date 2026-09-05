// Upgrade an existing Signalbox database; never rerun the fresh installer.
// Stop the API and workers and take a database backup before invoking this.
// ADMIN_DATABASE_URL=... node scripts/upgrade-policy-runtime.mjs
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { Client } from "pg";
import { installPolicyGuards } from "../dist/architecture/policy-guard.mjs";

assert.ok(process.env.ADMIN_DATABASE_URL, "ADMIN_DATABASE_URL is required");
const client = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
await client.connect();
try {
  const baseline = JSON.parse(await readFile("generated/signalbox/model.ir.json", "utf8"));
  const existing = await client.query("SELECT to_regclass('signalbox_architecture.policy_runtime_installation') AS installed");
  if (existing.rows[0].installed) {
    await client.query("SELECT signalbox_architecture.assert_policy_runtime($1)", [baseline.model.sourceHash]);
    console.log("Policy runtime already installed and verified; no migration applied.");
  } else {
    assert.ok((await client.query("SELECT to_regclass('model_signalbox.execution') AS installed")).rows[0].installed, "Expected an existing Signalbox database");
    await client.query(await readFile("sql/phase5_architecture.sql", "utf8"));
    await installPolicyGuards(client);
    await client.query("SELECT signalbox_architecture.assert_policy_runtime($1)", [baseline.model.sourceHash]);
    console.log("Policy runtime installed and verified. Install and activate a compatible bundle before accepting actions.");
  }
} finally { await client.end(); }
