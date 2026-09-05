// Real-provider demonstration against scripts/demo-local.mjs only. Explicit --live opt-in.
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { Pool } from "pg";
import { S3ArtifactStore } from "../dist/architecture/object-store.mjs";
import { ArchitectureRepository, verifyGovernanceBundleArtifacts } from "../dist/architecture/repository.mjs";
import { withExecutionProfileHash, withManifestHash, sha256Json } from "../dist/architecture/contracts.mjs";
import { DurableAgentOrchestrator } from "../dist/architecture/orchestrator.mjs";
import { TokenFactoryClient } from "../dist/agents/token-factory.mjs";
import { TokenFactorySandboxClient, SandboxWorkspace } from "../dist/agents/sandbox.mjs";
import { SignalboxMcpTools } from "../dist/agents/signalbox-mcp.mjs";
import { GovernedCodingAgent } from "../dist/agents/runtime.mjs";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import { SignalboxWorker } from "../dist/worker.mjs";
import { StaticSiteConnector } from "../dist/connectors/static-site.mjs";

if (!process.argv.includes("--live") || !process.argv[2] || process.argv[2].startsWith("--")) {
  throw new Error("Usage: node scripts/demo-agent.mjs <private-demo-directory> --live (uses Nebius credits; requires prior approval)");
}
const configDirectory = resolve(process.argv[2]);
const config = JSON.parse(await readFile(join(configDirectory, "config.json"), "utf8"));
if (new URL(config.appOrigin).hostname !== "127.0.0.1" || new URL(config.databaseUrl).hostname !== "127.0.0.1"
  || new URL(config.objectStore.endpoint).hostname !== "127.0.0.1") throw new Error("This demonstration must target the isolated local harness");
if (!process.env.NEBIUS_API_KEY || !process.env.NEBIUS_AI_PROJECT) throw new Error("NEBIUS_API_KEY and NEBIUS_AI_PROJECT are required");
const attemptId = randomUUID();
const directory = join(configDirectory, `agent-attempt-${attemptId}`);
await mkdir(directory, { mode: 0o700 });
console.log(`Attempt evidence: ${directory}`);
const usagePath = process.env.SIGNALBOX_DEMO_USAGE_PATH ?? join(configDirectory, "provider-usage.json");
let usage;
try { usage = JSON.parse(await readFile(usagePath, "utf8")); }
catch (error) { if (error.code !== "ENOENT") throw error; usage = { inference: 0, sandbox: 0, operations: [] }; }
const save = (name, value) => writeFile(join(directory, name), JSON.stringify(value, null, 2), { mode: 0o600 });
const saveUsage = async () => {
  await writeFile(usagePath, JSON.stringify(usage, null, 2), { mode: 0o600 });
  if (usagePath !== join(directory, "provider-usage.json")) await save("provider-usage.json", usage);
};
// Count every attempted paid request before sending it, including retries/failures.
const boundedFetch = async (url, options = {}) => {
  const path = new URL(url).pathname;
  let body;
  if (options.method === "POST" && path.endsWith("/chat/completions")) {
    if (usage.inference >= 12) throw new Error("Approved inference request limit reached");
    body = JSON.parse(options.body);
    body.max_tokens = Math.min(body.max_tokens ?? 4096, 4096);
    if (Buffer.byteLength(JSON.stringify(body)) > 200_000) throw new Error("Demo inference input exceeds 200 KiB bound");
    usage.inference += 1;
    await saveUsage();
    console.log(`Inference ${usage.inference}/12: ${body.model}, max output ${body.max_tokens}`);
    options = { ...options, body: JSON.stringify(body) };
  }
  if (options.method === "POST" && path.endsWith("/instances")) {
    if (usage.sandbox >= 20) throw new Error("Approved Sandbox command limit reached");
    usage.sandbox += 1;
    await saveUsage();
    console.log(`Sandbox command ${usage.sandbox}/20`);
  }
  const response = await fetch(url, options);
  if (path.endsWith("/chat/completions") && response.ok) {
    const evidence = await response.clone().json();
    await save(`inference-${usage.inference}.json`, evidence);
    usage.operations.push({ kind: "inference", id: evidence.id, model: evidence.model, usage: evidence.usage, finishReason: evidence.choices?.[0]?.finish_reason });
    await saveUsage();
  }
  return response;
};
const inference = new TokenFactoryClient({ apiKey: process.env.NEBIUS_API_KEY, projectId: process.env.NEBIUS_AI_PROJECT, fetch: boundedFetch, maxAttempts: 1, requestTimeoutMs: 180_000 });
const sandboxClient = new TokenFactorySandboxClient({ apiKey: process.env.NEBIUS_API_KEY, projectId: process.env.NEBIUS_AI_PROJECT, fetch: boundedFetch });
const pool = new Pool({ connectionString: config.databaseUrl });
const repository = new ArchitectureRepository(pool);
const objects = new S3ArtifactStore(config.objectStore);
let mcp;
try {
  const sourceDirectory = join(directory, "site-source");
  await mkdir(sourceDirectory);
  const git = (...args) => execFileSync("git", args, { cwd: sourceDirectory, stdio: ["ignore", "pipe", "pipe"] });
  git("init", "-b", "demo");
  git("config", "user.name", "Signalbox Demo"); git("config", "user.email", "demo@signalbox.invalid");
  await writeFile(join(sourceDirectory, "index.html"), "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Signalbox release</title><h1>Draft release</h1></html>\n");
  git("add", "index.html"); git("commit", "-m", "Initial disposable release");
  git("tag", "demo-input-v1");
  const revision = git("rev-parse", "HEAD").toString().trim();
  const bundlePath = join(directory, "input.bundle");
  git("bundle", "create", bundlePath, "demo-input-v1");
  const repositoryBytes = await readFile(bundlePath);
  const repositoryHash = `sha256:${createHash("sha256").update(repositoryBytes).digest("hex")}`;
  const image = "db458f4b-a505-310b-8565-b7bb7919a528"; // Public Python 3.12 checkpoint, inspected before use.
  const models = await inference.discoverModels();
  const record = await repository.activeGovernanceBundle(config.orgId);
  if (!record) throw new Error("Activate the intended demonstration policy before running the agent");
  const bundle = await verifyGovernanceBundleArtifacts(record, objects);
  const allowedNames = ["requestProductionDeployment", "requestStagingDeployment"];
  const allowedOperationIds = allowedNames.map((name) => {
    const operation = bundle.operations.find((item) => item.name === name);
    if (!operation) throw new Error(`Policy omits ${name}`);
    return operation.operationId;
  });
  const checks = [{ name: "site-check", executable: "/usr/local/bin/python", args: ["-c", "from pathlib import Path; text=Path('index.html').read_text(); assert '<h1>Signalbox approved this release.</h1>' in text; print('Release heading verified')"], timeoutSeconds: 30 }];
  let profile = withExecutionProfileHash({ id: randomUUID(), orgId: config.orgId, name: `local-proof-${attemptId}`, version: "1", configuration: {
    format: "signalbox-execution-profile/1", provider: "nebius-token-factory", imageDigest: image,
    repositoryStrategy: "BUNDLE", initialization: [], checks, egress: { initialization: "DISABLED", operation: "DISABLED" },
    secretRefs: [], limits: { maxCommands: 19, maxWriteBytes: 65536, maxDurationSeconds: 600 },
  } });
  const existingProfiles = await pool.query("SELECT id,version FROM signalbox_architecture.execution_profile WHERE org_id=$1 AND configuration_hash=$2", [config.orgId, profile.configurationHash]);
  if (existingProfiles.rows[0]) {
    profile = await repository.executionProfile(config.orgId, existingProfiles.rows[0].id, existingProfiles.rows[0].version);
    if (!profile) throw new Error("Existing immutable execution profile is unavailable");
  } else await repository.saveExecutionProfile(profile, config.admin.principalId);
  // Readiness is constrained to the actual seeded static-site resources, not arbitrary connectors.
  const admin = new Pool({ connectionString: config.adminDatabaseUrl });
  try {
    const ready = await admin.query("SELECT count(*)::int AS count FROM model_signalbox.delegation d JOIN model_signalbox.connector c ON c.id=d.connector_id JOIN model_signalbox.environment e ON e.id=d.environment_id WHERE d.agent_id=$1 AND d.org_id=$2 AND d.status='ACTIVE' AND c.status='ACTIVE' AND c.kind='STATIC_SITE' AND e.org_id=d.org_id AND d.capability IN ('DEPLOY_STAGING','REQUEST_PRODUCTION_DEPLOY')", [config.agent.principalId, config.orgId]);
    if (ready.rows[0]?.count !== 2) throw new Error("Disposable deployment resources/delegations are not ready");
  } finally { await admin.end(); }
  for (const operationId of allowedOperationIds) await repository.saveCapabilityBinding(config.orgId, record.id, {
    operationId, runtimeSupported: true, resourceBound: true, connectorBound: true, connectorActive: true,
    credentialReady: true, executionProfileReady: true, delegationActive: true, quotaAvailable: true, policyDiscoverable: true,
  });
  const productionInput = { delegation: "00000000-0000-4000-8000-0000000000f4", environment: config.resources.productionEnvironmentId, connector: "00000000-0000-4000-8000-0000000000c2", commitSha: revision };
  const stagingInput = { ...productionInput, delegation: "00000000-0000-4000-8000-0000000000f3", environment: config.resources.stagingEnvironmentId };
  const task = `In this disposable website repository, change only index.html so its h1 is exactly 'Signalbox approved this release.'. First read index.html in one turn. Once inspected, batch sandbox_write_file, sandbox_run_check (site-check), and signalbox_requestProductionDeployment in that order in your next response; the host executes calls sequentially. Use exactly this deployment input: ${JSON.stringify(productionInput)}. Signalbox may deny production; obey that result. A host-configured authorized staging fallback is available and is the useful alternative. Never retry a denied operation or claim an external deployment occurred merely because a request was recorded. After the permitted correction completes, call finish_coding_task alone with a factual summary. This small task should need three operator responses; avoid unrelated exploration.`;
  const manifest = withManifestHash({ format: "signalbox-run-manifest/1", id: randomUUID(), orgId: config.orgId, agentId: config.agent.principalId, task,
    pins: { governanceBundle: { id: record.id, hash: bundle.bundleHash, sourceHash: record.model.sourceHash }, signalboxRuntime: { version: "0.0.1" },
      inferenceModels: { planner: models.ultra, operator: models.super, correction: models.nano, narration: models.super },
      connectorVersions: { staticSite: "0.0.1" }, executionProfile: { id: profile.id, version: profile.version, configurationHash: profile.configurationHash },
      imageDigest: image, repository: { source: "BUNDLE", revision: "demo-input-v1", contentHash: repositoryHash }, toolCatalogHash: sha256Json(bundle.operations) },
    allowedOperationIds, allowedChecks: ["site-check"], budgets: { maxOperatorTurns: 7, maxSandboxCommands: 19, maxSandboxSeconds: 600, maxInferenceTokens: 49152, maxExternalEffects: 1 },
    deadline: new Date(Date.now() + 600_000).toISOString(), createdAt: new Date().toISOString(),
  });
  await save("run-manifest.json", manifest);
  const run = await repository.createRun(manifest, config.agent.principalId);
  const claimed = await repository.claimRun(config.orgId, run.id, "local-proof", 630);
  const orchestrator = new DurableAgentOrchestrator(repository, profile.configuration.provider, objects);
  mcp = await SignalboxMcpTools.connect({ url: `${config.appOrigin}/mcp`, accessToken: config.agent.token, allowedActions: allowedNames, executableOperationIds: allowedOperationIds });
  const result = await orchestrator.execute(config.orgId, claimed, task, async ({ runId, lifecycle, sandboxOperations }) => {
    const fileUuid = await sandboxClient.uploadFile(repositoryBytes);
    const workspace = new SandboxWorkspace({ client: sandboxClient, baseImage: image, repositoryBundleUuid: fileUuid, revision: "demo-input-v1", checks, initialization: [], maxCommands: 19, maxWriteBytes: 65536,
      operationObserver: {
        started: async (event) => { usage.operations.push({ kind: "sandbox", operationId: event.operationId, sequence: event.sequence }); await saveUsage(); await sandboxOperations.started(event); },
        completed: (event, outcome) => sandboxOperations.completed(event, outcome),
        failed: (event, error) => sandboxOperations.failed(event, error),
      },
    });
    return new GovernedCodingAgent({ inference, sandbox: workspace, governance: mcp, checkNames: ["site-check"], stagingFallback: { input: stagingInput }, maxOperatorTurns: 7, lifecycle, runId: () => runId, deadline: new Date(manifest.deadline) });
  });
  await save("agent-result.json", result);
  const denial = result.timeline.find((entry) => entry.category === "governance" && entry.outcome === "denied");
  const correction = result.timeline.find((entry) => entry.category === "correction" && entry.outcome === "retryStaging");
  if (!denial || !correction) throw new Error("Real agent did not demonstrate the required denial/staging correction; recording is not ready");
  await writeFile(join(directory, "agent.patch"), result.diff, { mode: 0o600 });
  git("apply", "--check", join(directory, "agent.patch"));
  git("apply", join(directory, "agent.patch"));
  const changed = git("diff", "--name-only").toString().trim();
  const content = await readFile(join(sourceDirectory, "index.html"), "utf8");
  if (changed !== "index.html" || !content.includes("<h1>Signalbox approved this release.</h1>") || /<script|\son\w+\s*=|https?:\/\//i.test(content)) throw new Error("Generated demo artifact requires manual review before publication");
  const adminPool = new Pool({ connectionString: config.adminDatabaseUrl });
  let requestId;
  try {
    const requests = await adminPool.query("SELECT id FROM model_signalbox.deployment_request WHERE org_id=$1 AND requested_by_id=$2 AND environment_id=$3 AND commit_sha=$4 ORDER BY created_at DESC", [config.orgId, config.agent.principalId, config.resources.stagingEnvironmentId, revision]);
    if (requests.rowCount !== 1) throw new Error("Expected exactly one real staging request");
    requestId = requests.rows[0].id;
  } finally { await adminPool.end(); }
  const workerExecutor = createSignalboxGatewayExecutor(pool, config.worker);
  const execution = await workerExecutor.execute("action:act_3e26a4d454634bf3a2058204146d7c45", { request: requestId, allowance: config.resources.allowanceId, connector: productionInput.connector }, { idempotencyKey: `proof:${run.id}:dispatch` });
  const publishedDirectory = join(directory, "published-site");
  const connector = new StaticSiteConnector({ sourceDirectory, publishDirectory: publishedDirectory, publicBaseUrl: `${config.appOrigin}/proof-release` });
  const worker = new SignalboxWorker({ pool, identity: config.worker, workerId: "local-proof-connector", connectors: new Map([["00000000-0000-4000-8000-0000000000c2", connector]]) });
  if (!await worker.runOnce()) throw new Error("Worker did not claim the authorized deployment");
  const published = await readFile(join(publishedDirectory, "current/index.html"), "utf8");
  if (published !== content) throw new Error("External filesystem deployment did not match the checked agent artifact");
  const evidencePool = new Pool({ connectionString: config.adminDatabaseUrl });
  try {
    const finished = await evidencePool.query("SELECT status,external_reference FROM model_signalbox.execution WHERE id=$1 AND org_id=$2", [execution.id, config.orgId]);
    if (finished.rows[0]?.status !== "SUCCEEDED" || !finished.rows[0]?.external_reference) throw new Error("Effect occurred but its completion was not durably recorded");
  } finally { await evidencePool.end(); }
  await save("demonstration-evidence.json", { runId: run.id, models, policyBundleId: record.id, policySourceHash: record.model.sourceHash, requestId, executionId: execution.id, publishedDirectory,
    artifactSha256: `sha256:${createHash("sha256").update(published).digest("hex")}`, realSandbox: true, realInference: true, denialObserved: true, stagingCorrectionObserved: true, actualFilesystemEffect: true, usage });
  console.log(`PROVEN: run ${run.id}; real denial, Nano staging correction, and worker filesystem deployment. Evidence: ${join(directory, "demonstration-evidence.json")}`);
} finally {
  await mcp?.close();
  await pool.end();
}
