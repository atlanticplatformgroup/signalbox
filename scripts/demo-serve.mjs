// Resume an existing private local proof environment without reseeding its evidence.
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join, resolve } from "node:path";
import { Pool } from "pg";
import { createSignalboxBoundary } from "../dist/boundary.mjs";
import { createSignalboxNodeServer } from "../dist/server.mjs";
import { GovernanceBundleCompiler } from "../dist/architecture/bundle-compiler.mjs";
import { S3ArtifactStore } from "../dist/architecture/object-store.mjs";
import { ArchitectureRepository } from "../dist/architecture/repository.mjs";
import { PostgresPolicyInstaller } from "../dist/architecture/policy-installer.mjs";

const directory = resolve(process.argv[2]);
const config = JSON.parse(await readFile(join(directory, "config.json"), "utf8"));
for (const url of [config.appOrigin, config.issuer, config.databaseUrl, config.adminDatabaseUrl, config.objectStore.endpoint]) {
  if (new URL(url).hostname !== "127.0.0.1") throw new Error("Only the isolated local harness can be resumed");
}
const pool = new Pool({ connectionString: config.databaseUrl });
const adminPool = new Pool({ connectionString: config.adminDatabaseUrl });
const repository = new ArchitectureRepository(pool);
const objectStore = new S3ArtifactStore(config.objectStore);
const compiler = new GovernanceBundleCompiler({ objectStore, compiler: resolve("node_modules/.bin/modelc") });
const installer = new PostgresPolicyInstaller(adminPool, repository, objectStore, compiler);
const jwks = await readFile(join(directory, "jwks.json"));
const oidc = createServer((request, response) => {
  response.writeHead(request.url === "/.well-known/jwks.json" ? 200 : 404, { "content-type": "application/json" });
  response.end(request.url === "/.well-known/jwks.json" ? jwks : "{}");
});
const boundary = createSignalboxBoundary({ pool, publicOrigin: config.appOrigin,
  identity: { oidc: { issuer: config.issuer, audience: config.audience } },
  governanceStudio: { repository, objectStore, compiler, installer, activity: async (identity) => {
    const result = await pool.query("SELECT * FROM signalbox_architecture.action_evidence($1,$2)", [identity.issuer, identity.subject]);
    return result.rows.map((row) => ({ id: row.id, operationId: row.operation_id, decision: row.decision,
      policyBundleId: row.policy_bundle_id, policySourceHash: row.policy_source_hash, createdAt: row.created_at, result: row.result }));
  } },
});
const app = createSignalboxNodeServer(boundary, config.appOrigin);
for (const [server, url] of [[oidc, config.issuer], [app, config.appOrigin]]) {
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(Number(new URL(url).port), "127.0.0.1", resolve); });
}
console.log(`Resumed local proof: ${config.appOrigin}/studio/`);
for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, async () => {
  app.closeAllConnections(); oidc.closeAllConnections(); app.close(); oidc.close();
  await Promise.all([pool.end(), adminPool.end()]); process.exit(0);
});
