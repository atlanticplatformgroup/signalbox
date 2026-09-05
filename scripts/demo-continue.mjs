// Continue a saved, real denial without repeating coding or Sandbox work.
// --live requires a separately approved increase from 12 to 14 total inference requests.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { Pool } from "pg";
import { TokenFactoryClient } from "../dist/agents/token-factory.mjs";
import { DenialCorrectionRole } from "../dist/agents/roles.mjs";
import { SignalboxMcpTools } from "../dist/agents/signalbox-mcp.mjs";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import { StaticSiteConnector } from "../dist/connectors/static-site.mjs";
import { SignalboxWorker } from "../dist/worker.mjs";

const config = JSON.parse(await readFile(join(resolve(process.argv[2]), "config.json"), "utf8"));
const directory = resolve(process.argv[3]);
const result = JSON.parse(await readFile(join(directory, "agent-result.json"), "utf8"));
const manifest = JSON.parse(await readFile(join(directory, "run-manifest.json"), "utf8"));
for (const url of [config.appOrigin, config.databaseUrl, config.adminDatabaseUrl]) assert.equal(new URL(url).hostname, "127.0.0.1");
const verificationPool = new Pool({ connectionString: config.databaseUrl });
try {
  const run = await verificationPool.query("SELECT manifest_id FROM signalbox_architecture.agent_run WHERE org_id=$1 AND id=$2", [config.orgId, result.runId]);
  assert.equal(run.rows[0]?.manifest_id, manifest.id);
} finally { await verificationPool.end(); }
const denial = result.timeline.find((entry) => entry.category === "governance" && entry.outcome === "denied");
assert.ok(denial);
assert.ok(result.timeline.some((entry) => entry.operation === "runCheck" && entry.outcome === "completed" && entry.evidence.exitCode === 0));
const sourceDirectory = join(directory, "site-source");
const git = (...args) => execFileSync("git", args, { cwd: sourceDirectory, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
const revision = git("rev-parse", "HEAD").trim();
const input = { delegation: "00000000-0000-4000-8000-0000000000f3", environment: config.resources.stagingEnvironmentId,
  connector: "00000000-0000-4000-8000-0000000000c2", commitSha: revision };
const resume = process.argv.includes("--resume");
if (!process.argv.includes("--live") && !resume) {
  console.log(JSON.stringify({ runId: result.runId, savedDenial: denial.evidence.denial.ruleId,
    proposedContinuation: "Ask Nano to select from the executable staging fallback, notifyHuman, or stop; independently authorize staging before any local worker effect.",
    maximumAdditionalInferenceRequests: 2, additionalSandboxCommands: 0, input, target: join(directory, "published-site") }, null, 2));
  process.exit(0);
}
assert.ok(process.env.SIGNALBOX_DEMO_USAGE_PATH, "Use the existing cumulative provider ledger");
const usagePath = process.env.SIGNALBOX_DEMO_USAGE_PATH;
const usage = JSON.parse(await readFile(usagePath, "utf8"));
const save = (name, value) => writeFile(join(directory, name), JSON.stringify(value, null, 2), { mode: 0o600 });
let correction;
if (resume) {
  correction = JSON.parse(await readFile(join(directory, "continuation-correction.json"), "utf8"));
} else {
const inference = new TokenFactoryClient({ apiKey: process.env.NEBIUS_API_KEY, projectId: process.env.NEBIUS_AI_PROJECT,
  maxAttempts: 1, requestTimeoutMs: 180_000, fetch: async (url, options = {}) => {
    if (options.method === "POST") {
      assert.ok(new URL(url).pathname.endsWith("/chat/completions"));
      assert.ok(usage.inference < 14, "Approved cumulative inference limit reached");
      const body = JSON.parse(options.body); body.max_tokens = Math.min(body.max_tokens ?? 1024, 1024);
      usage.inference += 1;
      await writeFile(usagePath, JSON.stringify(usage, null, 2), { mode: 0o600 });
      options = { ...options, body: JSON.stringify(body) };
    }
    const response = await fetch(url, options);
    if (options.method === "POST" && response.ok) {
      const evidence = await response.clone().json();
      await save(`continuation-inference-${usage.inference}.json`, evidence);
      usage.operations.push({ kind: "inference", id: evidence.id, model: evidence.model, usage: evidence.usage });
      await writeFile(usagePath, JSON.stringify(usage, null, 2), { mode: 0o600 });
    }
    return response;
  },
});
correction = await new DenialCorrectionRole(inference).correct({ ...denial.evidence.denial,
  decisionEvidence: { ...denial.evidence.denial.decisionEvidence, hostFallback: {
    task: "Publish the checked disposable website to staging instead of restricted production.",
    retryStaging: "The host has a configured staging target and scoped delegation; invoking it will be independently assessed. No policy or production approval is changed.",
    approval: "No approval request was created by the previous recommendation. This continuation has no approval-submission tool.",
  } },
}, ["retryStaging", "notifyHuman", "stop"]);
await save("continuation-correction.json", correction);
}
assert.equal(correction.action, "retryStaging", "Nano did not select staging; no effect will be performed");
const tools = await SignalboxMcpTools.connect({ url: `${config.appOrigin}/mcp`, accessToken: config.agent.token, allowedActions: ["requestStagingDeployment"] });
const pool = new Pool({ connectionString: config.databaseUrl });
const admin = new Pool({ connectionString: config.adminDatabaseUrl });
try {
  const staging = await tools.invoke("requestStagingDeployment", input, {
    idempotencyKey: `continuation:${result.runId}:staging`, correlationId: `agent:${result.runId}`,
  });
  await save("continuation-staging.json", staging);
  assert.equal(staging.outcome, "executed");
  const requests = await admin.query("SELECT id FROM model_signalbox.deployment_request WHERE org_id=$1 AND requested_by_id=$2 AND environment_id=$3 AND commit_sha=$4", [config.orgId, config.agent.principalId, config.resources.stagingEnvironmentId, revision]);
  assert.equal(requests.rowCount, 1);
  const requestId = requests.rows[0].id;
  const patch = join(directory, "agent.patch");
  await writeFile(patch, result.diff, { mode: 0o600 });
  if (git("diff").trim() !== result.diff.trim()) {
    assert.equal(git("status", "--porcelain").trim(), "", "Refuse to replace unexpected source changes");
    git("apply", "--check", patch); git("apply", patch);
  }
  assert.equal(git("diff", "--name-only").trim(), "index.html");
  const content = await readFile(join(sourceDirectory, "index.html"), "utf8");
  assert.ok(content.includes("<h1>Signalbox approved this release.</h1>"));
  assert.ok(!/<script|\son\w+\s*=|https?:\/\//i.test(content));
  const execution = await createSignalboxGatewayExecutor(pool, config.worker).execute("action:act_3e26a4d454634bf3a2058204146d7c45", { request: requestId, allowance: config.resources.allowanceId, connector: input.connector }, { idempotencyKey: `continuation:${result.runId}:dispatch` });
  const publishedDirectory = join(directory, "published-site");
  const worker = new SignalboxWorker({ pool, identity: config.worker, workerId: "local-proof-continuation",
    connectors: new Map([[input.connector, new StaticSiteConnector({ sourceDirectory, publishDirectory: publishedDirectory, publicBaseUrl: `${config.appOrigin}/proof-release` })]]) });
  const existing = await admin.query("SELECT status FROM model_signalbox.execution WHERE org_id=$1 AND id=$2", [config.orgId, execution.id]);
  if (existing.rows[0]?.status !== "SUCCEEDED") assert.equal(await worker.runOnce(), true);
  const published = await readFile(join(publishedDirectory, "current/index.html"), "utf8");
  assert.equal(published, content);
  const finished = await admin.query("SELECT status,external_reference FROM model_signalbox.execution WHERE org_id=$1 AND id=$2", [config.orgId, execution.id]);
  assert.equal(finished.rows[0]?.status, "SUCCEEDED"); assert.ok(finished.rows[0].external_reference);
  await save("demonstration-evidence.json", { runId: result.runId, continuation: true, originalCorrection: "requestApproval",
    finalCorrection: correction, requestId, executionId: execution.id, policyBundleId: manifest.pins.governanceBundle.id,
    artifactSha256: `sha256:${createHash("sha256").update(published).digest("hex")}`, publishedDirectory,
    realInference: true, realSandbox: true, actualFilesystemEffect: true, usage });
  console.log(`PROVEN: saved real agent run continued through Nano staging correction and local worker effect. Evidence: ${directory}/demonstration-evidence.json`);
} finally { await tools.close(); await pool.end(); await admin.end(); }
