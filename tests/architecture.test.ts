import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { GovernanceBundleCompiler } from "../src/architecture/bundle-compiler.mjs";
import {
  executionProfileFormat,
  runManifestFormat,
  sha256Json,
  withExecutionProfileHash,
  withManifestHash,
  verifyRunManifest,
  type CapabilityBindingState,
} from "../src/architecture/contracts.mjs";
import { MemoryArtifactStore } from "../src/architecture/object-store.mjs";
import { DurableAgentOrchestrator } from "../src/architecture/orchestrator.mjs";
import { ArchitectureRepository, GovernanceAdministrationError, RunTransitionConflictError } from "../src/architecture/repository.mjs";
import { closedOperations, missingPreparation, resolveBundleReadiness } from "../src/architecture/readiness.mjs";

const ORG = "00000000-0000-4000-8000-0000000000a1";
const ADMIN = "00000000-0000-4000-8000-0000000000b4";
const AGENT = "00000000-0000-4000-8000-0000000000b1";
const PROFILE = "00000000-0000-4000-8000-000000000501";
const MANIFEST = "00000000-0000-4000-8000-000000000601";
const databaseUrl = "postgresql://sb_gateway_login:gw@127.0.0.1:55433/sb_managed";
const migration = readFileSync(new URL("../sql/phase5_architecture.sql", import.meta.url), "utf8");
const pool = new Pool({ connectionString: databaseUrl });

const source = readFileSync(new URL("../signalbox.model", import.meta.url), "utf8");

function applyArchitectureSchema(): void {
  execFileSync("docker", ["exec", "-i", "sb-pg16", "psql", "-U", "nebius_admin", "-d", "sb_managed", "-v", "ON_ERROR_STOP=1", "-f", "-"], {
    input: `DROP SCHEMA IF EXISTS signalbox_architecture CASCADE;\n${migration}`,
    encoding: "utf8",
  });
}

function administrativeSql(statement: string): void {
  execFileSync("docker", ["exec", "-i", "sb-pg16", "psql", "-U", "nebius_admin", "-d", "sb_managed", "-v", "ON_ERROR_STOP=1", "-f", "-"], {
    input: statement,
    encoding: "utf8",
  });
}

function binding(operationId: string, overrides: Partial<CapabilityBindingState> = {}): CapabilityBindingState {
  return {
    operationId,
    runtimeSupported: true,
    resourceBound: true,
    connectorBound: true,
    connectorActive: true,
    credentialReady: true,
    executionProfileReady: true,
    delegationActive: true,
    quotaAvailable: true,
    policyDiscoverable: true,
    ...overrides,
  };
}

function profile() {
  return withExecutionProfileHash({
    id: PROFILE,
    orgId: ORG,
    name: "node-22",
    version: "1",
    configuration: {
      format: executionProfileFormat,
      provider: "nebius",
      imageDigest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      repositoryStrategy: "BUNDLE",
      initialization: [],
      checks: [{ name: "test", executable: "/usr/bin/npm", args: ["test"], timeoutSeconds: 180 }],
      egress: { initialization: "DISABLED", operation: "DISABLED" },
      secretRefs: [],
      limits: { maxCommands: 64, maxWriteBytes: 1_048_576, maxDurationSeconds: 900 },
    },
  });
}

beforeAll(() => applyArchitectureSchema());
afterAll(async () => { await pool.end(); });

describe("architecture contracts", () => {
  it("compiles the fixed Signalbox source into an immutable governance bundle in object storage", async () => {
    const objects = new MemoryArtifactStore();
    const compiler = new GovernanceBundleCompiler({ objectStore: objects });
    const compiled = await compiler.compile(ORG, source);
    expect(new TextDecoder().decode(await objects.get(compiled.sourceObject.key))).toBe(source);
    const storedBundle = JSON.parse(new TextDecoder().decode(await objects.get(compiled.bundleObject.key)));
    const { bundleHash, ...content } = storedBundle;
    expect(sha256Json(content)).toBe(bundleHash);
    expect(bundleHash).toBe(compiled.bundle.bundleHash);
    const rebuilt = await compiler.compile(ORG, source);
    expect(rebuilt.bundle.bundleHash).toBe(bundleHash);
    expect(rebuilt.bundleObject.key).toBe(compiled.bundleObject.key);
  });

  it("closes only fully prepared capabilities and returns a stop outcome for missing preparation", async () => {
    const compiled = await new GovernanceBundleCompiler({ objectStore: new MemoryArtifactStore() }).compile(ORG, source);
    const operationId = compiled.bundle.operations.find((operation) => operation.name === "requestIssueCreation")!.operationId;
    const states = [binding(operationId, {
      credentialReady: false,
      details: [{ code: "CREDENTIAL_UNAVAILABLE", message: "GitHub App installation credential is absent.", requirement: "github-app" }],
    })];
    const readiness = resolveBundleReadiness(compiled.bundle, states, "2026-08-31T00:00:00.000Z");
    expect(closedOperations(compiled.bundle, states).operations).toHaveLength(0);
    const selected = readiness.find((operation) => operation.operationId === operationId)!;
    expect(selected).toMatchObject({ ready: false, missing: [{ code: "CREDENTIAL_UNAVAILABLE", requirement: "github-app" }] });
    expect(missingPreparation(readiness, operationId)).toEqual({
      outcome: "MISSING_PREPARATION",
      operationId,
      missing: selected.missing,
      instruction: "STOP_AND_REPORT",
    });
  });

  it("hashes immutable execution profiles and complete run pins deterministically", () => {
    const executionProfile = profile();
    const base = {
      format: runManifestFormat,
      id: MANIFEST,
      orgId: ORG,
      agentId: AGENT,
      task: "Fix the failing test",
      pins: {
        governanceBundle: { id: "00000000-0000-4000-8000-000000000701", hash: "sha256:" + "b".repeat(64), sourceHash: "sha256:" + "c".repeat(64) },
        signalboxRuntime: { version: "1.0.0" },
        inferenceModels: { planner: "ultra", operator: "super", correction: "super", narration: "super" },
        connectorVersions: { github: "1" },
        executionProfile: { id: executionProfile.id, version: executionProfile.version, configurationHash: executionProfile.configurationHash },
        imageDigest: executionProfile.configuration.imageDigest,
        repository: { source: "BUNDLE" as const, revision: "main", contentHash: "sha256:" + "d".repeat(64) },
        toolCatalogHash: "sha256:" + "e".repeat(64),
      },
      allowedOperationIds: ["action:one"],
      allowedChecks: ["test"],
      budgets: { maxOperatorTurns: 12, maxSandboxCommands: 64, maxSandboxSeconds: 900, maxInferenceTokens: 100_000, maxExternalEffects: 2 },
      createdAt: "2026-08-31T00:00:00.000Z",
      deadline: "2026-08-31T00:15:00.000Z",
    };
    const manifest = withManifestHash(base);
    expect(manifest.manifestHash).toBe(sha256Json(base));
    expect(Object.isFrozen(manifest.pins.inferenceModels)).toBe(true);
    expect(executionProfile.configurationHash).toMatch(/^sha256:/);
    expect(() => verifyRunManifest({ ...manifest, task: "Tampered task" })).toThrow("hash does not match");
  });
});

describe("durable architecture repository", () => {
  it("requires current tenant administration at persistence and leaves active policy unchanged on corrupt activation or rollback", async () => {
    const adminId = randomUUID();
    const reviewerId = randomUUID();
    administrativeSql(`
      INSERT INTO model_signalbox.principal (id,org_id,kind,display_name,status,roles)
      VALUES ('${adminId}','${ORG}','HUMAN','Policy admin regression','ACTIVE','{ADMIN}'),
             ('${reviewerId}','${ORG}','HUMAN','Policy reviewer regression','ACTIVE','{MEMBER,APPROVER}');
    `);
    try {
      const objects = new MemoryArtifactStore();
      const compiler = new GovernanceBundleCompiler({ objectStore: objects });
      const compiled = await compiler.compile(ORG, source.replace(/(model Signalbox version )"[^"]+"/, '$1"0.8.0"'));
      const repository = new ArchitectureRepository(pool);
      await expect(repository.saveCompiledBundle(ORG, reviewerId, compiled)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      await expect(repository.saveCompiledBundle(ORG, AGENT, compiled)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      await expect(repository.saveCompiledBundle("00000000-0000-4000-8000-0000000000a2", adminId, compiled)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      const firstId = await repository.saveCompiledBundle(ORG, adminId, compiled);
      await expect(repository.activateBundle(ORG, firstId, reviewerId, objects)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      await repository.activateBundle(ORG, firstId, adminId, objects);
      expect((await repository.activeGovernanceBundle(ORG))?.id).toBe(firstId);
      await expect(pool.query("UPDATE signalbox_architecture.governance_bundle SET status='RETIRED' WHERE id=$1", [firstId])).rejects.toMatchObject({ code: "42501" });

      const next = await compiler.compile(ORG, source.replace(/(model Signalbox version )"[^"]+"/, '$1"0.9.0"'));
      const nextId = await repository.saveCompiledBundle(ORG, adminId, next);
      administrativeSql(`UPDATE model_signalbox.principal SET roles='{MEMBER,APPROVER}' WHERE id='${adminId}';`);
      await expect(repository.activateBundle(ORG, nextId, adminId, objects)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      administrativeSql(`UPDATE model_signalbox.principal SET roles='{ADMIN}',status='REVOKED' WHERE id='${adminId}';`);
      await expect(repository.saveCompiledBundle(ORG, adminId, next)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      await expect(repository.activateBundle(ORG, nextId, adminId, objects)).rejects.toBeInstanceOf(GovernanceAdministrationError);
      expect((await repository.activeGovernanceBundle(ORG))?.id).toBe(firstId);
      administrativeSql(`UPDATE model_signalbox.principal SET status='ACTIVE' WHERE id='${adminId}';`);

      const corruptSource = {
        put: objects.put.bind(objects),
        get: async (key: string) => key === next.sourceObject.key ? Buffer.from("tampered policy") : objects.get(key),
      };
      await expect(repository.activateBundle(ORG, nextId, adminId, corruptSource)).rejects.toThrow();
      expect((await repository.activeGovernanceBundle(ORG))?.id).toBe(firstId);
      await repository.activateBundle(ORG, nextId, adminId, objects);
      const corruptRollback = {
        put: objects.put.bind(objects),
        get: async (key: string) => key === compiled.bundleObject.key
          ? Buffer.from(JSON.stringify({ ...compiled.bundle, preview: {} }))
          : objects.get(key),
      };
      await expect(repository.activateBundle(ORG, firstId, adminId, corruptRollback)).rejects.toThrow();
      expect(await repository.activeGovernanceBundle(ORG)).toMatchObject({ id: nextId, previousBundleId: firstId });
    } finally {
      administrativeSql(`DELETE FROM model_signalbox.principal WHERE id IN ('${adminId}','${reviewerId}');`);
    }
  });

  it("persists bundle/profile pins, enforces readiness, and records run and sandbox transitions", async () => {
    const objects = new MemoryArtifactStore();
    const compiled = await new GovernanceBundleCompiler({ objectStore: objects }).compile(ORG, source);
    const repository = new ArchitectureRepository(pool);
    const bundleId = await repository.saveCompiledBundle(ORG, ADMIN, compiled);
    const executionProfile = profile();
    await repository.saveExecutionProfile(executionProfile, ADMIN);
    await repository.activateBundle(ORG, bundleId, ADMIN, objects);
    const operationId = compiled.bundle.operations.find((operation) => operation.name === "requestIssueCreation")!.operationId;

    const manifestBase = {
      format: runManifestFormat,
      id: MANIFEST,
      orgId: ORG,
      agentId: AGENT,
      task: "Fix the failing test",
      pins: {
        governanceBundle: { id: bundleId, hash: compiled.bundle.bundleHash, sourceHash: compiled.bundle.model.sourceHash },
        signalboxRuntime: { version: "1.0.0" },
        inferenceModels: { planner: "ultra", operator: "super", correction: "super", narration: "super" },
        connectorVersions: { github: "1" },
        executionProfile: { id: executionProfile.id, version: executionProfile.version, configurationHash: executionProfile.configurationHash },
        imageDigest: executionProfile.configuration.imageDigest,
        repository: { source: "BUNDLE" as const, revision: "main", contentHash: "sha256:" + "d".repeat(64) },
        toolCatalogHash: sha256Json(compiled.bundle.operations),
      },
      allowedOperationIds: [operationId],
      allowedChecks: ["test"],
      budgets: { maxOperatorTurns: 12, maxSandboxCommands: 64, maxSandboxSeconds: 900, maxInferenceTokens: 100_000, maxExternalEffects: 2 },
      createdAt: "2026-08-31T00:00:00.000Z",
      deadline: "2026-08-31T00:15:00.000Z",
    };
    const manifest = withManifestHash(manifestBase);
    await expect(repository.createRun(manifest, ADMIN)).rejects.toMatchObject({
      outcome: "MISSING_PREPARATION",
      instruction: "STOP_AND_REPORT",
      operationIds: [operationId],
    });

    await repository.saveCapabilityBinding(ORG, bundleId, binding(operationId));
    await repository.createRun(manifest, ADMIN);
    const resolving = await repository.claimNextRun(ORG, "worker-a", 60);
    expect(resolving).toMatchObject({ state: "RESOLVING", stateVersion: 1, manifestId: MANIFEST });
    if (!resolving) throw new Error("Expected a claimed run");
    await repository.renewRunLease(ORG, resolving.id, "worker-a", 60);
    await expect(repository.transitionRun(ORG, resolving.id, "QUEUED", 0, "RESOLVING", {})).rejects.toBeInstanceOf(RunTransitionConflictError);

    const orchestrator = new DurableAgentOrchestrator(repository, "nebius", objects);
    const result = await orchestrator.execute(ORG, resolving, manifest.task, ({ runId, lifecycle, sandboxOperations }) => ({
      run: async () => {
        await lifecycle.transition("PLANNING", { initialized: true });
        await lifecycle.transition("OPERATING", { planSteps: 1 });
        const event = {
          sequence: 1,
          operationId: "sandbox-op-1",
          command: { image: "tag:node-22", executable: "/usr/bin/npm", args: ["test"] },
        };
        await sandboxOperations.started(event);
        await sandboxOperations.completed(event, {
          operationId: event.operationId,
          resultImage: "image:result-1",
          exitCode: 0,
          timedOut: false,
          stdout: "ok",
          stderr: "",
          stdoutTruncated: false,
          stderrTruncated: false,
        });
        await lifecycle.transition("VERIFYING", { checks: ["test"] });
        return {
          runId,
          plan: { summary: "Run the focused check", steps: [{ objective: "test", expectedEvidence: "pass" }], risks: [] },
          summary: "Completed",
          diff: "",
          narration: { summary: "Completed", controls: [], unresolved: [], evidence: ["test passed"] },
          timeline: [],
        };
      },
    }));
    expect(result.runId).toBe(resolving.id);
    const persisted = await pool.query(
      `SELECT op.result_image,op.state,run.state AS run_state,run.completed_at
       FROM signalbox_architecture.sandbox_operation op
       JOIN signalbox_architecture.agent_run run ON run.id=op.run_id
       WHERE op.run_id=$1`,
      [resolving.id],
    );
    const artifacts = await pool.query(
      "SELECT kind FROM signalbox_architecture.run_artifact WHERE run_id=$1 ORDER BY kind",
      [resolving.id],
    );
    expect(artifacts.rows).toEqual([{ kind: "DIFF" }, { kind: "LOG" }]);
    expect(persisted.rows[0]).toMatchObject({ result_image: "image:result-1", state: "SUCCEEDED", run_state: "COMPLETED" });
    expect(persisted.rows[0].completed_at).toBeInstanceOf(Date);
  });
});
