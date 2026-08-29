import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";
import type { Pool, PoolClient } from "pg";
import {
  ConnectorFailure,
  type ExecutionClaim,
  type ExecutionConnector,
  requireString,
  throwIfAborted,
} from "./connector.mjs";

export interface PostgreSqlMigrationConnectorOptions {
  readonly pool: Pick<Pool, "connect">;
  readonly migrationsDirectory: string;
  readonly statementTimeoutMs?: number;
  readonly lockTimeoutMs?: number;
}

export class PostgreSqlMigrationConnector implements ExecutionConnector {
  readonly kind = "POSTGRESQL" as const;
  private readonly migrationsDirectory: string;
  private readonly statementTimeoutMs: number;
  private readonly lockTimeoutMs: number;

  constructor(private readonly options: PostgreSqlMigrationConnectorOptions) {
    this.migrationsDirectory = resolve(options.migrationsDirectory);
    this.statementTimeoutMs = boundedTimeout(options.statementTimeoutMs ?? 30_000, "statementTimeoutMs");
    this.lockTimeoutMs = boundedTimeout(options.lockTimeoutMs ?? 5_000, "lockTimeoutMs");
  }

  async recover(claim: ExecutionClaim, signal: AbortSignal): Promise<string | undefined> {
    if (claim.requestKind !== "SCHEMA_MIGRATION") throw new ConnectorFailure("CONNECTOR_KIND_MISMATCH", false);
    throwIfAborted(signal);
    const environmentId = requireString(claim.payload, "environmentId");
    const migrationName = requireString(claim.payload, "migrationName");
    const expectedSha = requireString(claim.payload, "migrationSha").toLowerCase();
    const client = await this.options.pool.connect();
    try {
      const result = await client.query<{ migration_sha: string; execution_id: string }>(
        `SELECT migration_sha, execution_id
           FROM public.signalbox_schema_migrations
          WHERE environment_id = $1 AND migration_name = $2`,
        [environmentId, migrationName],
      );
      const row = result.rows[0];
      if (!row) return undefined;
      if (row.migration_sha !== expectedSha) throw new ConnectorFailure("MIGRATION_LEDGER_CONFLICT", false);
      return migrationReference(environmentId, migrationName, row.execution_id);
    } catch (error) {
      if (error instanceof ConnectorFailure) throw error;
      if (hasErrorCode(error, "42P01")) return undefined;
      throw new ConnectorFailure("POSTGRESQL_TRANSIENT", true, { cause: error });
    } finally {
      client.release();
    }
  }

  async execute(claim: ExecutionClaim, signal: AbortSignal): Promise<string> {
    if (claim.requestKind !== "SCHEMA_MIGRATION") throw new ConnectorFailure("CONNECTOR_KIND_MISMATCH", false);
    throwIfAborted(signal);
    const environmentId = requireString(claim.payload, "environmentId");
    const migrationName = requireString(claim.payload, "migrationName");
    const expectedSha = requireString(claim.payload, "migrationSha").toLowerCase();
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(migrationName) || migrationName.includes("..")) {
      throw new ConnectorFailure("MIGRATION_NAME_INVALID", false);
    }
    if (!/^[a-f0-9]{64}$/.test(expectedSha)) throw new ConnectorFailure("MIGRATION_SHA_INVALID", false);
    const migrationPath = resolve(this.migrationsDirectory, `${migrationName}.sql`);
    const pathFromRoot = relative(this.migrationsDirectory, migrationPath);
    if (pathFromRoot.startsWith(`..${sep}`) || pathFromRoot === ".." || isAbsolute(pathFromRoot)) {
      throw new ConnectorFailure("MIGRATION_NAME_INVALID", false);
    }

    let migrationSql: string;
    try {
      migrationSql = await readFile(migrationPath, "utf8");
    } catch (error) {
      throw new ConnectorFailure("MIGRATION_NOT_FOUND", false, { cause: error });
    }
    const actualSha = createHash("sha256").update(migrationSql).digest("hex");
    if (actualSha !== expectedSha) throw new ConnectorFailure("MIGRATION_CHECKSUM_MISMATCH", false);
    const statements = splitSqlStatements(migrationSql);
    if (statements.length === 0) throw new ConnectorFailure("MIGRATION_EMPTY", false);
    for (const statement of statements) {
      if (TRANSACTION_COMMANDS.has(firstKeyword(statement))) {
        throw new ConnectorFailure("MIGRATION_TRANSACTION_CONTROL", false);
      }
    }

    let client: PoolClient | undefined;
    let transactionOpen = false;
    let discardClient = false;
    try {
      client = await this.options.pool.connect();
      throwIfAborted(signal);
      await client.query("BEGIN");
      transactionOpen = true;
      await client.query(`SET LOCAL statement_timeout = '${this.statementTimeoutMs}ms'`);
      await client.query(`SET LOCAL lock_timeout = '${this.lockTimeoutMs}ms'`);
      await client.query("SELECT pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended($1, 0))", [
        `signalbox:${environmentId}:${migrationName}`,
      ]);
      await client.query(`
        CREATE TABLE IF NOT EXISTS public.signalbox_schema_migrations (
          environment_id uuid NOT NULL,
          migration_name text NOT NULL,
          migration_sha text NOT NULL,
          execution_id uuid NOT NULL,
          applied_at timestamptz NOT NULL DEFAULT pg_catalog.transaction_timestamp(),
          PRIMARY KEY (environment_id, migration_name)
        )
      `);
      const prior = await client.query<{ migration_sha: string; execution_id: string }>(
        `SELECT migration_sha, execution_id
           FROM public.signalbox_schema_migrations
          WHERE environment_id = $1 AND migration_name = $2
          FOR UPDATE`,
        [environmentId, migrationName],
      );
      if (prior.rows[0]) {
        if (prior.rows[0].migration_sha !== expectedSha) {
          throw new ConnectorFailure("MIGRATION_LEDGER_CONFLICT", false);
        }
        await client.query("COMMIT");
        transactionOpen = false;
        return migrationReference(environmentId, migrationName, prior.rows[0].execution_id);
      }
      for (const statement of statements) {
        throwIfAborted(signal);
        await client.query(statement);
      }
      throwIfAborted(signal);
      await client.query(
        `INSERT INTO public.signalbox_schema_migrations
           (environment_id, migration_name, migration_sha, execution_id)
         VALUES ($1, $2, $3, $4)`,
        [environmentId, migrationName, expectedSha, claim.executionId],
      );
      await client.query("COMMIT");
      transactionOpen = false;
      return migrationReference(environmentId, migrationName, claim.executionId);
    } catch (error) {
      if (client && transactionOpen) {
        try {
          await client.query("ROLLBACK");
        } catch {
          discardClient = true;
        }
      }
      if (error instanceof ConnectorFailure) throw error;
      if (signal.aborted) throw new ConnectorFailure("CONNECTOR_TIMEOUT", true, { cause: error });
      const code = errorCode(error);
      if (code.startsWith("08")) discardClient = true;
      const retryable = code.startsWith("08")
        || code === "40001"
        || code === "40P01"
        || code === "55P03"
        || code === "57014"
        || code === "57P01"
        || code === "57P02"
        || code === "57P03";
      throw new ConnectorFailure(retryable ? "POSTGRESQL_TRANSIENT" : "MIGRATION_EXECUTION_FAILED", retryable, { cause: error });
    } finally {
      client?.release(discardClient);
    }
  }
}

const TRANSACTION_COMMANDS = new Set([
  "ABORT", "BEGIN", "COMMIT", "END", "PREPARE", "RELEASE", "ROLLBACK", "SAVEPOINT", "START",
]);

function boundedTimeout(value: number, name: string): number {
  if (!Number.isInteger(value) || value < 100 || value > 300_000) throw new Error(`${name} must be an integer from 100 to 300000`);
  return value;
}

function migrationReference(environmentId: string, migrationName: string, executionId: string): string {
  return `postgresql://migration/${encodeURIComponent(environmentId)}/${encodeURIComponent(migrationName)}?execution=${encodeURIComponent(executionId)}`;
}

function errorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error && typeof error.code === "string") {
    return error.code;
  }
  return "";
}

function hasErrorCode(error: unknown, expected: string): boolean {
  return errorCode(error) === expected;
}

function firstKeyword(statement: string): string {
  let index = 0;
  while (index < statement.length) {
    while (/\s/.test(statement[index] ?? "")) index += 1;
    if (statement.startsWith("--", index)) {
      const end = statement.indexOf("\n", index + 2);
      index = end < 0 ? statement.length : end + 1;
      continue;
    }
    if (statement.startsWith("/*", index)) {
      const end = statement.indexOf("*/", index + 2);
      index = end < 0 ? statement.length : end + 2;
      continue;
    }
    break;
  }
  return /^[a-zA-Z]+/.exec(statement.slice(index))?.[0]?.toUpperCase() ?? "";
}

export function splitSqlStatements(sql: string): string[] {
  const statements: string[] = [];
  let start = 0;
  let index = 0;
  let state: "normal" | "single" | "double" | "line" | "block" | "dollar" = "normal";
  let blockDepth = 0;
  let dollarTag = "";
  while (index < sql.length) {
    const current = sql[index]!;
    const next = sql[index + 1];
    if (state === "normal") {
      if (current === "'") state = "single";
      else if (current === '"') state = "double";
      else if (current === "-" && next === "-") { state = "line"; index += 1; }
      else if (current === "/" && next === "*") { state = "block"; blockDepth = 1; index += 1; }
      else if (current === "$") {
        const match = /^\$[a-zA-Z_][a-zA-Z0-9_]*\$|^\$\$/.exec(sql.slice(index));
        if (match) { state = "dollar"; dollarTag = match[0]; index += dollarTag.length - 1; }
      } else if (current === ";") {
        const statement = sql.slice(start, index).trim();
        if (statement) statements.push(statement);
        start = index + 1;
      }
    } else if (state === "single") {
      if (current === "\\") index += 1;
      else
      if (current === "'" && next === "'") index += 1;
      else if (current === "'") state = "normal";
    } else if (state === "double") {
      if (current === '"' && next === '"') index += 1;
      else if (current === '"') state = "normal";
    } else if (state === "line") {
      if (current === "\n") state = "normal";
    } else if (state === "block") {
      if (current === "/" && next === "*") { blockDepth += 1; index += 1; }
      else if (current === "*" && next === "/") {
        blockDepth -= 1;
        index += 1;
        if (blockDepth === 0) state = "normal";
      }
    } else if (state === "dollar" && sql.startsWith(dollarTag, index)) {
      index += dollarTag.length - 1;
      state = "normal";
    }
    index += 1;
  }
  if (state !== "normal" && state !== "line") throw new ConnectorFailure("MIGRATION_SQL_UNTERMINATED", false);
  const trailing = sql.slice(start).trim();
  if (trailing) statements.push(trailing);
  return statements;
}
