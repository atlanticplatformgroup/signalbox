// Applies the Signalbox database boundary in dependency order.
//
// This is a fresh-install path. The generated DDL uses plain CREATE
// statements, so re-running against an installed database fails loudly rather
// than half-applying. Install into an empty database.
//
// The installing role needs CREATEDB and CREATEROLE. It does NOT need to be a
// superuser: 001_roles.sql re-grants each created role to the installer WITH
// SET TRUE so the later SET ROLE statements succeed, which is what makes
// managed PostgreSQL a valid target.
//
//   ADMIN_DATABASE_URL=... node scripts/install-database.mjs [--seed]
//
// --seed additionally loads the demo organization, principals, connectors,
// delegations, and allowances from seed.sql.

import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import pg from "pg";

const GENERATED = "generated/signalbox/postgres";
const PHASES = ["sql/phase2_auth.sql", "sql/phase3_worker.sql", "sql/phase5_architecture.sql"];

const databaseUrl = process.env.ADMIN_DATABASE_URL;
if (!databaseUrl) throw new Error("ADMIN_DATABASE_URL is required (CREATEDB + CREATEROLE)");

const seed = process.argv.includes("--seed");

let generated;
try {
  generated = (await readdir(GENERATED)).filter((name) => name.endsWith(".sql")).sort();
} catch {
  throw new Error(`${GENERATED} not found. Run 'npm run modellang:build' first.`);
}
if (generated.length === 0) throw new Error(`${GENERATED} contains no SQL. Run 'npm run modellang:build' first.`);

const files = [
  ...generated.map((name) => join(GENERATED, name)),
  ...PHASES,
  ...(seed ? ["seed.sql"] : []),
];

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  for (const file of files) {
    const sql = await readFile(file, "utf8");
    process.stdout.write(`${file.padEnd(48)}`);
    try {
      // Sent whole, not split: these files contain dollar-quoted function
      // bodies that a semicolon-based splitter would corrupt.
      await client.query(sql);
      process.stdout.write("OK\n");
    } catch (error) {
      process.stdout.write("FAILED\n");
      throw new Error(`${file} failed: ${error.message}`, { cause: error });
    }
  }
  process.stdout.write(`\n${files.length} files applied.\n`);
  if (!seed) process.stdout.write("Run again with --seed, or apply seed.sql, to load the demo organization.\n");
} finally {
  await client.end();
}
