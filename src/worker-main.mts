import { hostname } from "node:os";
import { dirname, resolve } from "node:path";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import type { ExecutionConnector } from "./connectors/connector.mjs";
import { GitHubAppConnector } from "./connectors/github-app.mjs";
import { PostgreSqlMigrationConnector } from "./connectors/postgresql-migration.mjs";
import { StaticSiteConnector } from "./connectors/static-site.mjs";
import { SignalboxWorker } from "./worker.mjs";

const databaseUrl = requiredEnvironment("DATABASE_URL");
const issuer = requiredEnvironment("SIGNALBOX_WORKER_ISSUER");
const subject = requiredEnvironment("SIGNALBOX_WORKER_SUBJECT");
const configPath = resolve(requiredEnvironment("CONNECTOR_CONFIG_PATH"));
const configDirectory = dirname(configPath);
const config = objectValue(JSON.parse(await readFile(configPath, "utf8")), "worker configuration");
const connectorRows = arrayValue(config.connectors, "connectors");
const gatewayPool = new Pool({ connectionString: databaseUrl, max: 4, application_name: "signalbox-worker" });
const targetPools: Pool[] = [];
const connectors = new Map<string, ExecutionConnector>();

try {
  for (const value of connectorRows) {
    const row = objectValue(value, "connector");
    const id = stringValue(row.id, "connector.id");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
      throw new Error("connector.id must be a UUID");
    }
    if (connectors.has(id)) throw new Error(`duplicate connector.id: ${id}`);
    const kind = stringValue(row.kind, "connector.kind");
    let connector: ExecutionConnector;
    if (kind === "GITHUB") {
      const privateKeyPath = localPath(row.privateKeyPath, "connector.privateKeyPath");
      connector = new GitHubAppConnector({
        appId: stringValue(row.appId, "connector.appId"),
        installationId: stringValue(row.installationId, "connector.installationId"),
        privateKeyPem: await readFile(privateKeyPath, "utf8"),
        apiBaseUrl: optionalString(row.apiBaseUrl, "connector.apiBaseUrl"),
      });
    } else if (kind === "STATIC_SITE") {
      connector = new StaticSiteConnector({
        sourceDirectory: localPath(row.sourceDirectory, "connector.sourceDirectory"),
        publishDirectory: localPath(row.publishDirectory, "connector.publishDirectory"),
        publicBaseUrl: stringValue(row.publicBaseUrl, "connector.publicBaseUrl"),
      });
    } else if (kind === "POSTGRESQL") {
      const connectionStringEnvironment = stringValue(row.connectionStringEnv, "connector.connectionStringEnv");
      const targetPool = new Pool({
        connectionString: requiredEnvironment(connectionStringEnvironment),
        max: 2,
        application_name: "signalbox-migration-worker",
      });
      targetPools.push(targetPool);
      connector = new PostgreSqlMigrationConnector({
        pool: targetPool,
        migrationsDirectory: localPath(row.migrationsDirectory, "connector.migrationsDirectory"),
        statementTimeoutMs: optionalInteger(row.statementTimeoutMs, "connector.statementTimeoutMs"),
        lockTimeoutMs: optionalInteger(row.lockTimeoutMs, "connector.lockTimeoutMs"),
      });
    } else {
      throw new Error(`unsupported connector.kind: ${kind}`);
    }
    connectors.set(id, connector);
  }

  const worker = new SignalboxWorker({
    pool: gatewayPool,
    identity: { issuer, subject },
    workerId: optionalString(config.workerId, "workerId") ?? `${hostname()}:${process.pid}`,
    connectors,
    leaseSeconds: optionalInteger(config.leaseSeconds, "leaseSeconds"),
    connectorTimeoutMs: optionalInteger(config.connectorTimeoutMs, "connectorTimeoutMs"),
    maxAttempts: optionalInteger(config.maxAttempts, "maxAttempts"),
    retryBaseMs: optionalInteger(config.retryBaseMs, "retryBaseMs"),
    retryMaxMs: optionalInteger(config.retryMaxMs, "retryMaxMs"),
  });
  const pollIntervalMs = optionalInteger(config.pollIntervalMs, "pollIntervalMs") ?? 1_000;
  if (pollIntervalMs < 10 || pollIntervalMs > 60_000) throw new Error("pollIntervalMs must be from 10 to 60000");
  let stopping = false;
  process.once("SIGINT", () => { stopping = true; });
  process.once("SIGTERM", () => { stopping = true; });
  while (!stopping) {
    if (!await worker.runOnce()) await delay(pollIntervalMs);
  }
} finally {
  await Promise.allSettled(targetPools.map((pool) => pool.end()));
  await gatewayPool.end();
}

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function objectValue(value: unknown, name: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} must be an object`);
  return Object.fromEntries(Object.entries(value));
}

function arrayValue(value: unknown, name: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(`${name} must be an array`);
  return value;
}

function stringValue(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) throw new Error(`${name} must be a non-empty string`);
  return value;
}

function optionalString(value: unknown, name: string): string | undefined {
  return value === undefined ? undefined : stringValue(value, name);
}

function optionalInteger(value: unknown, name: string): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "number" || !Number.isInteger(value)) throw new Error(`${name} must be an integer`);
  return value;
}

function localPath(value: unknown, name: string): string {
  return resolve(configDirectory, stringValue(value, name));
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}
