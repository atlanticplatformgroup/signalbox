import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { pathToFileURL } from "node:url";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { Pool } from "pg";
import { readFile } from "node:fs/promises";
import { createSignalboxBoundary, type SignalboxBoundary } from "./boundary.mjs";
import { GovernanceBundleCompiler } from "./architecture/bundle-compiler.mjs";
import { s3ArtifactStoreFromEnvironment } from "./architecture/object-store.mjs";
import { ArchitectureRepository } from "./architecture/repository.mjs";
import { PostgresPolicyInstaller } from "./architecture/policy-installer.mjs";

async function toRequest(request: IncomingMessage, publicOrigin: string): Promise<Request> {
  const body = request.method === "GET" || request.method === "HEAD"
    ? undefined
    : Readable.toWeb(request) as ReadableStream;
  return new Request(new URL(request.url ?? "/", publicOrigin), {
    method: request.method,
    headers: request.headers as HeadersInit,
    body,
    duplex: body ? "half" : undefined,
  } as RequestInit);
}

async function send(source: Response, target: ServerResponse): Promise<void> {
  target.writeHead(source.status, Object.fromEntries(source.headers.entries()));
  if (!source.body) {
    target.end();
    return;
  }
  await pipeline(Readable.fromWeb(source.body as never), target);
}

export function createSignalboxNodeServer(boundary: SignalboxBoundary, publicOrigin: string): Server {
  return createServer(async (request, response) => {
    try {
      await send(await boundary.fetch(await toRequest(request, publicOrigin)), response);
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      if (!response.headersSent) {
        await send(new Response("Internal Server Error", { status: 500 }), response);
      } else {
        response.destroy();
      }
    }
  });
}

export async function startSignalboxServer(): Promise<{ server: Server; pool: Pool; policyPool: Pool }> {
  const databaseUrl = process.env.DATABASE_URL;
  const publicOrigin = process.env.PUBLIC_ORIGIN;
  const policyDatabaseUrl = process.env.SIGNALBOX_POLICY_DATABASE_URL;
  if (!policyDatabaseUrl) throw new Error("SIGNALBOX_POLICY_DATABASE_URL is required for isolated policy installation");
  if (!databaseUrl || !publicOrigin) throw new Error("DATABASE_URL and PUBLIC_ORIGIN are required");
  if ((process.env.OIDC_ISSUER && !process.env.OIDC_AUDIENCE)
    || (!process.env.OIDC_ISSUER && process.env.OIDC_AUDIENCE)) {
    throw new Error("OIDC_ISSUER and OIDC_AUDIENCE must be configured together");
  }

  const pool = new Pool({ connectionString: databaseUrl });
  try {
    const baseline = JSON.parse(await readFile("generated/signalbox/model.ir.json", "utf8"));
    await pool.query("SELECT signalbox_architecture.assert_policy_runtime($1)", [baseline.model.sourceHash]);
  } catch (error) {
    await pool.end();
    throw error;
  }
  const policyPool = new Pool({ connectionString: policyDatabaseUrl, max: 2 });
  const objectStore = s3ArtifactStoreFromEnvironment();
  const architecture = new ArchitectureRepository(pool);
  const bundleCompiler = new GovernanceBundleCompiler({
    objectStore,
    ...(process.env.MODELC_PATH ? { compiler: process.env.MODELC_PATH } : {}),
  });
  const boundary = createSignalboxBoundary({
    pool,
    publicOrigin,
    agentTokenIssuer: process.env.AGENT_TOKEN_ISSUER,
    identity: {
      githubApiUrl: process.env.GITHUB_API_URL,
      ...(process.env.OIDC_ISSUER && process.env.OIDC_AUDIENCE
        ? { oidc: { issuer: process.env.OIDC_ISSUER, audience: process.env.OIDC_AUDIENCE } }
        : {}),
    },
    governanceStudio: {
      repository: architecture,
      compiler: bundleCompiler,
      objectStore,
      installer: new PostgresPolicyInstaller(policyPool, architecture, objectStore, bundleCompiler),
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
  const server = createSignalboxNodeServer(boundary, publicOrigin);
  const port = Number(process.env.PORT ?? "4310");
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) throw new Error("PORT must be an integer from 1 through 65535");
  const host = process.env.BIND_ADDRESS ?? "127.0.0.1";
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  return { server, pool, policyPool };
}

const main = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (main) {
  const { server, pool, policyPool } = await startSignalboxServer();
  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => {
      server.close(() => void Promise.all([pool.end(), policyPool.end()]).finally(() => process.exit(0)));
    });
  }
}
