import { createHash } from "node:crypto";
import { hostname } from "node:os";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { Pool } from "pg";
import { GovernedCodingAgent } from "./agents/runtime.mjs";
import { SandboxWorkspace, TokenFactorySandboxClient } from "./agents/sandbox.mjs";
import { SignalboxMcpTools } from "./agents/signalbox-mcp.mjs";
import { TokenFactoryClient, type NemotronModels } from "./agents/token-factory.mjs";
import { objectValue, optionalString, stringValue } from "./agents/validation.mjs";
import { sha256Json, verifyRunManifest, type GovernanceBundle, type RunManifest } from "./architecture/contracts.mjs";
import { s3ArtifactStoreFromEnvironment } from "./architecture/object-store.mjs";
import { DurableAgentOrchestrator } from "./architecture/orchestrator.mjs";
import { ArchitectureRepository } from "./architecture/repository.mjs";

const configPath = resolve(requiredEnvironment("SIGNALBOX_AGENT_CONFIG_PATH"));
const config = objectValue(JSON.parse(await readFile(configPath, "utf8")), "agent configuration");
const manifest = verifyRunManifest(objectValue(config.manifest, "manifest") as unknown as RunManifest);
if (manifest.pins.signalboxRuntime.version !== "0.0.1") {
  throw new Error("Run manifest Signalbox runtime version is not installed");
}
const apiKey = requiredEnvironment("NEBIUS_API_KEY");
const projectId = requiredEnvironment("NEBIUS_AI_PROJECT");
const pool = new Pool({ connectionString: requiredEnvironment("DATABASE_URL") });
const objectStore = s3ArtifactStoreFromEnvironment();
const repository = new ArchitectureRepository(pool);
const bundleRecord = await repository.governanceBundle(manifest.orgId, manifest.pins.governanceBundle.id);
if (!bundleRecord) throw new Error("Run manifest governance bundle is unavailable");
const bundle = parsePinnedBundle(await objectStore.get(bundleRecord.bundleObjectKey), manifest);
const profile = await repository.executionProfile(
  manifest.orgId,
  manifest.pins.executionProfile.id,
  manifest.pins.executionProfile.version,
);
if (!profile) throw new Error("Run manifest execution profile is unavailable");
if (profile.configuration.repositoryStrategy !== manifest.pins.repository.source) {
  throw new Error("Run manifest repository source does not match the execution profile");
}
const checks = profile.configuration.checks.filter((check) => manifest.allowedChecks.includes(check.name));
if (checks.length !== manifest.allowedChecks.length) throw new Error("Run manifest contains a check absent from its execution profile");
const repositoryUrl = optionalString(config.repositoryUrl, "repositoryUrl");
const repositoryBundlePath = optionalString(config.repositoryBundlePath, "repositoryBundlePath");
if ((repositoryUrl === undefined) === (repositoryBundlePath === undefined)) {
  throw new Error("agent configuration requires exactly one repositoryUrl or repositoryBundlePath");
}
if ((manifest.pins.repository.source === "BUNDLE") !== (repositoryBundlePath !== undefined)) {
  throw new Error("Agent repository input does not match the immutable RunManifest source");
}
const repositoryBundle = repositoryBundlePath === undefined ? undefined : await readFile(resolve(repositoryBundlePath));
if (repositoryBundle) {
  const contentHash = `sha256:${createHash("sha256").update(repositoryBundle).digest("hex")}`;
  if (!manifest.pins.repository.contentHash || contentHash !== manifest.pins.repository.contentHash) {
    throw new Error("Repository bundle does not match the immutable RunManifest content hash");
  }
}

const queued = await repository.createRun(manifest, manifest.agentId);
const workerId = `${hostname()}:${process.pid}`;
const leaseSeconds = Math.min(3_600, Math.max(60, profile.configuration.limits.maxDurationSeconds + 30));
const claimed = await repository.claimRun(manifest.orgId, queued.id, workerId, leaseSeconds);
const orchestrator = new DurableAgentOrchestrator(repository, profile.configuration.provider, objectStore);
let signalbox: SignalboxMcpTools | undefined;
let models: NemotronModels | undefined;

try {
  const result = await orchestrator.execute(manifest.orgId, claimed, manifest.task, async ({ runId, lifecycle, sandboxOperations }) => {
    if (profile.configuration.initialization.some((step) => step.networking === "RESTRICTED_REGISTRIES")) {
      const error = new Error("Execution profile initialization requires a restricted-registry egress adapter that is not configured");
      error.name = "MISSING_PREPARATION";
      throw error;
    }
    const inference = new TokenFactoryClient({
      apiKey,
      projectId,
      baseUrl: optionalString(config.tokenFactoryBaseUrl, "tokenFactoryBaseUrl"),
    });
    models = await inference.discoverModels();
    verifyInferencePins(models, manifest);
    const sandboxClient = new TokenFactorySandboxClient({
      apiKey,
      projectId,
      baseUrl: optionalString(config.sandboxBaseUrl, "sandboxBaseUrl"),
    });
    const repositoryBundleUuid = repositoryBundle === undefined ? undefined : await sandboxClient.uploadFile(repositoryBundle);
    signalbox = await SignalboxMcpTools.connect({
      url: requiredEnvironment("SIGNALBOX_MCP_URL"),
      accessToken: requiredEnvironment("SIGNALBOX_AGENT_TOKEN"),
      allowedActions: bundle.operations
        .filter((operation) => manifest.allowedOperationIds.includes(operation.operationId))
        .map((operation) => operation.name),
      executableOperationIds: manifest.allowedOperationIds,
    });
    const sandbox = new SandboxWorkspace({
      client: sandboxClient,
      baseImage: manifest.pins.imageDigest,
      repositoryUrl,
      repositoryBundleUuid,
      revision: manifest.pins.repository.revision,
      checks,
      initialization: profile.configuration.initialization,
      workspaceRoot: optionalString(config.workspaceRoot, "workspaceRoot"),
      gitExecutable: optionalString(config.gitExecutable, "gitExecutable"),
      catExecutable: optionalString(config.catExecutable, "catExecutable"),
      teeExecutable: optionalString(config.teeExecutable, "teeExecutable"),
      mkdirExecutable: optionalString(config.mkdirExecutable, "mkdirExecutable"),
      maxCommands: manifest.budgets.maxSandboxCommands,
      maxWriteBytes: profile.configuration.limits.maxWriteBytes,
      operationObserver: sandboxOperations,
    });
    return new GovernedCodingAgent({
      inference,
      sandbox,
      governance: signalbox,
      checkNames: manifest.allowedChecks,
      maxOperatorTurns: manifest.budgets.maxOperatorTurns,
      lifecycle,
      runId: () => runId,
      deadline: new Date(manifest.deadline),
    });
  });
  process.stdout.write(`${JSON.stringify({ models, manifestHash: manifest.manifestHash, ...result }, null, 2)}\n`);
} finally {
  await signalbox?.close();
  await pool.end();
}

function parsePinnedBundle(content: Uint8Array, manifestValue: RunManifest): GovernanceBundle {
  const value = JSON.parse(new TextDecoder().decode(content)) as GovernanceBundle;
  const { bundleHash, ...unsigned } = value;
  if (bundleHash !== manifestValue.pins.governanceBundle.hash
    || sha256Json(unsigned) !== bundleHash
    || value.model.sourceHash !== manifestValue.pins.governanceBundle.sourceHash) {
    throw new Error("Governance bundle does not match the immutable RunManifest pins");
  }
  if (sha256Json(value.operations) !== manifestValue.pins.toolCatalogHash) {
    throw new Error("Governance tool catalog does not match the immutable RunManifest pin");
  }
  const operationIds = new Set(value.operations.map((operation) => operation.operationId));
  if (manifestValue.allowedOperationIds.some((operationId) => !operationIds.has(operationId))) {
    throw new Error("Run manifest allows an operation absent from its governance bundle");
  }
  return value;
}

function verifyInferencePins(modelsValue: NemotronModels, manifestValue: RunManifest): void {
  const expected = manifestValue.pins.inferenceModels;
  if (modelsValue.ultra !== expected.planner
    || modelsValue.super !== expected.operator
    || modelsValue.nano !== expected.correction
    || modelsValue.super !== expected.narration) {
    throw new Error("Discovered inference models do not match the immutable RunManifest pins");
  }
}

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}
