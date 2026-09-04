import { randomUUID } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import type { CompiledGovernanceBundle } from "./bundle-compiler.mjs";
import {
  withExecutionProfileHash,
  type CapabilityBindingState,
  type GovernanceBundle,
  type RunManifest,
  type VersionedExecutionProfile,
} from "./contracts.mjs";
import type { ArtifactKind, StoredObject } from "./object-store.mjs";

export type RunState =
  | "QUEUED"
  | "RESOLVING"
  | "PREPARING_ENVIRONMENT"
  | "PLANNING"
  | "OPERATING"
  | "AWAITING_APPROVAL"
  | "EXECUTING_EFFECT"
  | "VERIFYING"
  | "COMPLETED"
  | "FAILED"
  | "CANCELLED"
  | "TIMED_OUT"
  | "BUDGET_EXHAUSTED"
  | "PREPARATION_FAILED"
  | "RECOVERY_REQUIRED";

export interface DurableRun {
  readonly id: string;
  readonly manifestId: string;
  readonly state: RunState;
  readonly stateVersion: number;
  readonly failureCode: string | null;
  readonly failureDetail: string | null;
}

export interface GovernanceBundleRecord {
  readonly id: string;
  readonly orgId: string;
  readonly status: "COMPILED" | "ACTIVE" | "RETIRED";
  readonly model: GovernanceBundle["model"];
  readonly bundleHash: string;
  readonly sourceObjectKey: string;
  readonly bundleObjectKey: string;
  readonly previousBundleId: string | null;
  readonly createdBy: string;
  readonly createdAt: string;
  readonly activatedBy: string | null;
  readonly activatedAt: string | null;
}

export interface SandboxOperationRecord {
  readonly runId: string;
  readonly sequence: number;
  readonly provider: string;
  readonly operationId: string;
  readonly inputImage: string;
  readonly resultImage: string | null;
  readonly state: "STARTED" | "SUCCEEDED" | "FAILED" | "TIMED_OUT" | "UNKNOWN";
  readonly exitCode: number | null;
  readonly timedOut: boolean | null;
}

const terminalStates = new Set<RunState>(["COMPLETED", "FAILED", "CANCELLED", "TIMED_OUT", "BUDGET_EXHAUSTED", "PREPARATION_FAILED", "RECOVERY_REQUIRED"]);
const transitions: Readonly<Record<RunState, ReadonlySet<RunState>>> = {
  QUEUED: new Set(["RESOLVING", "CANCELLED", "TIMED_OUT"]),
  RESOLVING: new Set(["PREPARING_ENVIRONMENT", "PREPARATION_FAILED", "CANCELLED", "TIMED_OUT"]),
  PREPARING_ENVIRONMENT: new Set(["PLANNING", "PREPARATION_FAILED", "RECOVERY_REQUIRED", "CANCELLED", "TIMED_OUT"]),
  PLANNING: new Set(["OPERATING", "FAILED", "BUDGET_EXHAUSTED", "CANCELLED", "TIMED_OUT"]),
  OPERATING: new Set(["AWAITING_APPROVAL", "EXECUTING_EFFECT", "VERIFYING", "FAILED", "BUDGET_EXHAUSTED", "CANCELLED", "TIMED_OUT"]),
  AWAITING_APPROVAL: new Set(["OPERATING", "EXECUTING_EFFECT", "FAILED", "CANCELLED", "TIMED_OUT"]),
  EXECUTING_EFFECT: new Set(["OPERATING", "VERIFYING", "FAILED", "RECOVERY_REQUIRED", "TIMED_OUT"]),
  VERIFYING: new Set(["COMPLETED", "FAILED", "BUDGET_EXHAUSTED", "TIMED_OUT"]),
  COMPLETED: new Set(),
  FAILED: new Set(),
  CANCELLED: new Set(),
  TIMED_OUT: new Set(),
  BUDGET_EXHAUSTED: new Set(),
  PREPARATION_FAILED: new Set(),
  RECOVERY_REQUIRED: new Set(),
};

export class ArchitectureRepository {
  constructor(private readonly pool: Pool) {}

  async saveCompiledBundle(orgId: string, createdBy: string, compiled: CompiledGovernanceBundle): Promise<string> {
    return this.#transaction(async (client) => {
      const sourceArtifactId = await this.#saveArtifact(client, orgId, "MODEL_SOURCE", compiled.sourceObject);
      const bundleArtifactId = await this.#saveArtifact(client, orgId, "GOVERNANCE_BUNDLE", compiled.bundleObject);
      const result = await client.query<{ id: string }>(
        `INSERT INTO signalbox_architecture.governance_bundle (
          id, org_id, model_name, model_version, source_hash, bundle_hash, compiler_version,
          runtime_compatibility, source_artifact_id, bundle_artifact_id, operation_ids, status, created_by
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,'COMPILED',$12)
        ON CONFLICT (org_id, source_hash) DO UPDATE SET source_hash = EXCLUDED.source_hash
        RETURNING id`,
        [compiled.id, orgId, compiled.bundle.model.name, compiled.bundle.model.version, compiled.bundle.model.sourceHash,
          compiled.bundle.bundleHash, compiled.bundle.compilerVersion, compiled.bundle.runtimeCompatibility,
          sourceArtifactId, bundleArtifactId, JSON.stringify(compiled.bundle.operations.map((operation) => operation.operationId)), createdBy],
      );
      return result.rows[0]!.id;
    });
  }

  async activateBundle(orgId: string, bundleId: string, activatedBy: string): Promise<{ id: string; previousBundleId: string | null }> {
    return this.#transaction(async (client) => {
      const candidate = await client.query<{ id: string; status: string }>(
        "SELECT id, status FROM signalbox_architecture.governance_bundle WHERE org_id=$1 AND id=$2 FOR UPDATE",
        [orgId, bundleId],
      );
      if (!candidate.rows[0]) throw new Error("Governance bundle does not exist");
      const current = await client.query<{ id: string }>(
        "SELECT id FROM signalbox_architecture.governance_bundle WHERE org_id=$1 AND status='ACTIVE' FOR UPDATE",
        [orgId],
      );
      const previousBundleId = current.rows[0]?.id ?? null;
      if (previousBundleId === bundleId) return { id: bundleId, previousBundleId: null };
      if (previousBundleId) {
        await client.query("UPDATE signalbox_architecture.governance_bundle SET status='RETIRED' WHERE org_id=$1 AND id=$2", [orgId, previousBundleId]);
      }
      await client.query(
        `UPDATE signalbox_architecture.governance_bundle
         SET status='ACTIVE',previous_bundle_id=$3,activated_by=$4,activated_at=transaction_timestamp()
         WHERE org_id=$1 AND id=$2`,
        [orgId, bundleId, previousBundleId, activatedBy],
      );
      return { id: bundleId, previousBundleId };
    });
  }

  async governanceBundle(orgId: string, bundleId: string): Promise<GovernanceBundleRecord | null> {
    const result = await this.pool.query<Record<string, unknown>>(
      `SELECT bundle.*,source.object_key AS source_object_key,artifact.object_key AS bundle_object_key
       FROM signalbox_architecture.governance_bundle bundle
       JOIN signalbox_architecture.object_artifact source ON source.id=bundle.source_artifact_id
       JOIN signalbox_architecture.object_artifact artifact ON artifact.id=bundle.bundle_artifact_id
       WHERE bundle.org_id=$1 AND bundle.id=$2`,
      [orgId, bundleId],
    );
    return result.rows[0] ? governanceBundleRecord(result.rows[0]) : null;
  }

  async activeGovernanceBundle(orgId: string): Promise<GovernanceBundleRecord | null> {
    const result = await this.pool.query<Record<string, unknown>>(
      `SELECT bundle.*,source.object_key AS source_object_key,artifact.object_key AS bundle_object_key
       FROM signalbox_architecture.governance_bundle bundle
       JOIN signalbox_architecture.object_artifact source ON source.id=bundle.source_artifact_id
       JOIN signalbox_architecture.object_artifact artifact ON artifact.id=bundle.bundle_artifact_id
       WHERE bundle.org_id=$1 AND bundle.status='ACTIVE'`,
      [orgId],
    );
    return result.rows[0] ? governanceBundleRecord(result.rows[0]) : null;
  }

  async saveExecutionProfile(profile: VersionedExecutionProfile, createdBy: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO signalbox_architecture.execution_profile (
        id, org_id, name, version, provider, image_digest, configuration_hash, configuration, status, created_by
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,'ACTIVE',$9)`,
      [profile.id, profile.orgId, profile.name, profile.version, profile.configuration.provider, profile.configuration.imageDigest,
        profile.configurationHash, JSON.stringify(profile.configuration), createdBy],
    );
  }

  async executionProfile(orgId: string, profileId: string, version: string): Promise<VersionedExecutionProfile | null> {
    const result = await this.pool.query<Record<string, unknown>>(
      `SELECT id,org_id,name,version,configuration,configuration_hash
       FROM signalbox_architecture.execution_profile
       WHERE org_id=$1 AND id=$2 AND version=$3 AND status='ACTIVE'`,
      [orgId, profileId, version],
    );
    if (!result.rows[0]) return null;
    const row = result.rows[0];
    const verified = withExecutionProfileHash({
      id: String(row.id),
      orgId: String(row.org_id),
      name: String(row.name),
      version: String(row.version),
      configuration: row.configuration as VersionedExecutionProfile["configuration"],
    });
    if (verified.configurationHash !== String(row.configuration_hash)) {
      throw new Error("Execution profile configuration does not match its immutable hash");
    }
    return verified;
  }

  async saveCapabilityBinding(orgId: string, bundleId: string, state: CapabilityBindingState): Promise<void> {
    await this.pool.query(
      `INSERT INTO signalbox_architecture.capability_binding (
        org_id,bundle_id,operation_id,runtime_supported,resource_bound,connector_bound,connector_active,
        credential_ready,execution_profile_ready,delegation_active,quota_available,policy_discoverable,missing_details,checked_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb,transaction_timestamp())
      ON CONFLICT (org_id,bundle_id,operation_id) DO UPDATE SET
        runtime_supported=EXCLUDED.runtime_supported, resource_bound=EXCLUDED.resource_bound,
        connector_bound=EXCLUDED.connector_bound, connector_active=EXCLUDED.connector_active,
        credential_ready=EXCLUDED.credential_ready, execution_profile_ready=EXCLUDED.execution_profile_ready,
        delegation_active=EXCLUDED.delegation_active, quota_available=EXCLUDED.quota_available,
        policy_discoverable=EXCLUDED.policy_discoverable, missing_details=EXCLUDED.missing_details,
        checked_at=transaction_timestamp()`,
      [orgId, bundleId, state.operationId, state.runtimeSupported, state.resourceBound, state.connectorBound,
        state.connectorActive, state.credentialReady, state.executionProfileReady, state.delegationActive,
        state.quotaAvailable, state.policyDiscoverable, JSON.stringify(state.details ?? [])],
    );
  }

  async capabilityBindings(orgId: string, bundleId: string): Promise<CapabilityBindingState[]> {
    const result = await this.pool.query<Record<string, unknown>>(
      "SELECT * FROM signalbox_architecture.capability_binding WHERE org_id=$1 AND bundle_id=$2 ORDER BY operation_id",
      [orgId, bundleId],
    );
    return result.rows.map((row) => ({
      operationId: String(row.operation_id),
      runtimeSupported: Boolean(row.runtime_supported),
      resourceBound: Boolean(row.resource_bound),
      connectorBound: Boolean(row.connector_bound),
      connectorActive: Boolean(row.connector_active),
      credentialReady: Boolean(row.credential_ready),
      executionProfileReady: Boolean(row.execution_profile_ready),
      delegationActive: Boolean(row.delegation_active),
      quotaAvailable: Boolean(row.quota_available),
      policyDiscoverable: Boolean(row.policy_discoverable),
      details: Array.isArray(row.missing_details) ? row.missing_details as CapabilityBindingState["details"] : [],
    }));
  }

  async createRun(manifest: RunManifest, createdBy: string): Promise<DurableRun> {
    return this.#transaction(async (client) => {
      const ready = await client.query<{ operation_id: string }>(
        `SELECT operation_id FROM signalbox_architecture.capability_binding
         WHERE org_id=$1 AND bundle_id=$2 AND runtime_supported AND resource_bound AND connector_bound
           AND connector_active AND credential_ready AND execution_profile_ready AND delegation_active
           AND quota_available AND policy_discoverable`,
        [manifest.orgId, manifest.pins.governanceBundle.id],
      );
      const readyIds = new Set(ready.rows.map((row) => row.operation_id));
      const unavailable = manifest.allowedOperationIds.filter((operationId) => !readyIds.has(operationId));
      if (unavailable.length) throw new MissingPreparationError(unavailable);
      const bundle = await client.query(
        "SELECT 1 FROM signalbox_architecture.governance_bundle WHERE org_id=$1 AND id=$2 AND status='ACTIVE' AND bundle_hash=$3 AND source_hash=$4",
        [manifest.orgId, manifest.pins.governanceBundle.id, manifest.pins.governanceBundle.hash, manifest.pins.governanceBundle.sourceHash],
      );
      if (!bundle.rowCount) throw new Error("Run manifest governance bundle pin is not the active immutable bundle");
      const profile = await client.query(
        "SELECT 1 FROM signalbox_architecture.execution_profile WHERE org_id=$1 AND id=$2 AND version=$3 AND configuration_hash=$4 AND image_digest=$5 AND status='ACTIVE'",
        [manifest.orgId, manifest.pins.executionProfile.id, manifest.pins.executionProfile.version,
          manifest.pins.executionProfile.configurationHash, manifest.pins.imageDigest],
      );
      if (!profile.rowCount) throw new Error("Run manifest execution profile pin is unavailable or changed");
      await client.query(
        `INSERT INTO signalbox_architecture.run_manifest
          (id,org_id,agent_id,bundle_id,execution_profile_id,manifest_hash,manifest,created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8)`,
        [manifest.id, manifest.orgId, manifest.agentId, manifest.pins.governanceBundle.id,
          manifest.pins.executionProfile.id, manifest.manifestHash, JSON.stringify(manifest), createdBy],
      );
      const runId = randomUUID();
      await client.query(
        "INSERT INTO signalbox_architecture.agent_run (id,org_id,manifest_id,state) VALUES ($1,$2,$3,'QUEUED')",
        [runId, manifest.orgId, manifest.id],
      );
      await client.query(
        "INSERT INTO signalbox_architecture.run_transition (run_id,sequence,from_state,to_state,evidence) VALUES ($1,1,NULL,'QUEUED',$2::jsonb)",
        [runId, JSON.stringify({ manifestHash: manifest.manifestHash })],
      );
      return { id: runId, manifestId: manifest.id, state: "QUEUED", stateVersion: 0, failureCode: null, failureDetail: null };
    });
  }
  async claimNextRun(orgId: string, workerId: string, leaseSeconds = 60): Promise<DurableRun | null> {
    if (!workerId || workerId.length > 200) throw new TypeError("Worker ID must contain 1-200 characters");
    if (!Number.isSafeInteger(leaseSeconds) || leaseSeconds < 5 || leaseSeconds > 3_600) {
      throw new TypeError("Run lease must be an integer from 5 to 3600 seconds");
    }
    return this.#transaction(async (client) => {
      const claimed = await client.query<{ id: string; manifest_id: string; state_version: string }>(
        `WITH candidate AS (
           SELECT id FROM signalbox_architecture.agent_run
           WHERE org_id=$1 AND state='QUEUED'
           ORDER BY created_at,id
           FOR UPDATE SKIP LOCKED
           LIMIT 1
         )
         UPDATE signalbox_architecture.agent_run AS run SET
           state='RESOLVING',
           state_version=run.state_version+1,
           lease_owner=$2,
           lease_expires_at=transaction_timestamp()+make_interval(secs => $3),
           updated_at=transaction_timestamp()
         FROM candidate
         WHERE run.id=candidate.id
         RETURNING run.id,run.manifest_id,run.state_version`,
        [orgId, workerId, leaseSeconds],
      );
      if (!claimed.rows[0]) return null;
      await client.query(
        `INSERT INTO signalbox_architecture.run_transition (run_id,sequence,from_state,to_state,evidence)
         SELECT $1,COALESCE(MAX(sequence),0)+1,'QUEUED','RESOLVING',$2::jsonb
         FROM signalbox_architecture.run_transition WHERE run_id=$1`,
        [claimed.rows[0].id, JSON.stringify({ workerId, leaseSeconds })],
      );
      return {
        id: claimed.rows[0].id,
        manifestId: claimed.rows[0].manifest_id,
        state: "RESOLVING",
        stateVersion: Number(claimed.rows[0].state_version),
        failureCode: null,
        failureDetail: null,
      };
    });
  }

  async claimRun(orgId: string, runId: string, workerId: string, leaseSeconds = 60): Promise<DurableRun> {
    if (!workerId || workerId.length > 200) throw new TypeError("Worker ID must contain 1-200 characters");
    if (!Number.isSafeInteger(leaseSeconds) || leaseSeconds < 5 || leaseSeconds > 3_600) {
      throw new TypeError("Run lease must be an integer from 5 to 3600 seconds");
    }
    return this.#transaction(async (client) => {
      const claimed = await client.query<{ manifest_id: string; state_version: string }>(
        `UPDATE signalbox_architecture.agent_run SET
           state='RESOLVING',state_version=state_version+1,lease_owner=$3,
           lease_expires_at=transaction_timestamp()+make_interval(secs => $4),updated_at=transaction_timestamp()
         WHERE org_id=$1 AND id=$2 AND state='QUEUED'
         RETURNING manifest_id,state_version`,
        [orgId, runId, workerId, leaseSeconds],
      );
      if (!claimed.rows[0]) throw new Error("Run is not queued or does not exist");
      await client.query(
        `INSERT INTO signalbox_architecture.run_transition (run_id,sequence,from_state,to_state,evidence)
         SELECT $1,COALESCE(MAX(sequence),0)+1,'QUEUED','RESOLVING',$2::jsonb
         FROM signalbox_architecture.run_transition WHERE run_id=$1`,
        [runId, JSON.stringify({ workerId, leaseSeconds })],
      );
      return {
        id: runId,
        manifestId: claimed.rows[0].manifest_id,
        state: "RESOLVING",
        stateVersion: Number(claimed.rows[0].state_version),
        failureCode: null,
        failureDetail: null,
      };
    });
  }

  async renewRunLease(orgId: string, runId: string, workerId: string, leaseSeconds = 60): Promise<void> {
    if (!Number.isSafeInteger(leaseSeconds) || leaseSeconds < 5 || leaseSeconds > 3_600) {
      throw new TypeError("Run lease must be an integer from 5 to 3600 seconds");
    }
    const renewed = await this.pool.query(
      `UPDATE signalbox_architecture.agent_run
       SET lease_expires_at=transaction_timestamp()+make_interval(secs => $4),updated_at=transaction_timestamp()
       WHERE org_id=$1 AND id=$2 AND lease_owner=$3 AND state NOT IN
         ('COMPLETED','FAILED','CANCELLED','TIMED_OUT','BUDGET_EXHAUSTED','PREPARATION_FAILED','RECOVERY_REQUIRED')`,
      [orgId, runId, workerId, leaseSeconds],
    );
    if (renewed.rowCount !== 1) throw new Error("Run lease renewal did not match one active claimed run");
  }


  async transitionRun(
    orgId: string,
    runId: string,
    expectedState: RunState,
    expectedVersion: number,
    nextState: RunState,
    evidence: Readonly<Record<string, unknown>>,
    failure?: { readonly code: string; readonly detail: string },
  ): Promise<DurableRun> {
    if (!transitions[expectedState].has(nextState)) throw new Error(`Invalid agent run transition ${expectedState} -> ${nextState}`);
    return this.#transaction(async (client) => {
      const current = await client.query<{ state: RunState; state_version: string; manifest_id: string }>(
        "SELECT state,state_version,manifest_id FROM signalbox_architecture.agent_run WHERE org_id=$1 AND id=$2 FOR UPDATE",
        [orgId, runId],
      );
      if (!current.rows[0]) throw new Error("Agent run does not exist");
      if (current.rows[0].state !== expectedState || Number(current.rows[0].state_version) !== expectedVersion) {
        throw new RunTransitionConflictError(current.rows[0].state, Number(current.rows[0].state_version));
      }
      const nextVersion = expectedVersion + 1;
      await client.query(
        `UPDATE signalbox_architecture.agent_run SET state=$3,state_version=$4,updated_at=transaction_timestamp(),
          completed_at=CASE WHEN $5 THEN transaction_timestamp() ELSE NULL END,
          lease_owner=CASE WHEN $5 THEN NULL ELSE lease_owner END,
          lease_expires_at=CASE WHEN $5 THEN NULL ELSE lease_expires_at END,
          failure_code=$6,failure_detail=$7 WHERE org_id=$1 AND id=$2`,
        [orgId, runId, nextState, nextVersion, terminalStates.has(nextState), failure?.code ?? null, failure?.detail ?? null],
      );
      await client.query(
        `INSERT INTO signalbox_architecture.run_transition (run_id,sequence,from_state,to_state,evidence)
         SELECT $1,COALESCE(MAX(sequence),0)+1,$2,$3,$4::jsonb FROM signalbox_architecture.run_transition WHERE run_id=$1`,
        [runId, expectedState, nextState, JSON.stringify(evidence)],
      );
      return { id: runId, manifestId: current.rows[0].manifest_id, state: nextState, stateVersion: nextVersion, failureCode: failure?.code ?? null, failureDetail: failure?.detail ?? null };
    });
  }

  async startSandboxOperation(record: Omit<SandboxOperationRecord, "resultImage" | "state" | "exitCode" | "timedOut">): Promise<void> {
    await this.pool.query(
      `INSERT INTO signalbox_architecture.sandbox_operation
        (run_id,sequence,provider,operation_id,input_image,state)
       VALUES ($1,$2,$3,$4,$5,'STARTED')`,
      [record.runId, record.sequence, record.provider, record.operationId, record.inputImage],
    );
  }

  async completeSandboxOperation(record: SandboxOperationRecord): Promise<void> {
    if (record.state === "STARTED") throw new TypeError("A completed sandbox operation cannot remain STARTED");
    const result = await this.pool.query(
      `UPDATE signalbox_architecture.sandbox_operation SET
        result_image=$3,state=$4,exit_code=$5,timed_out=$6,completed_at=transaction_timestamp()
       WHERE run_id=$1 AND sequence=$2 AND state='STARTED' AND provider=$7 AND operation_id=$8`,
      [record.runId, record.sequence, record.resultImage, record.state, record.exitCode, record.timedOut, record.provider, record.operationId],
    );
    if (result.rowCount !== 1) throw new Error("Sandbox operation completion did not match one started operation");
  }

  async saveRunArtifact(
    orgId: string,
    runId: string,
    kind: "DIFF" | "LOG" | "OTHER",
    sequence: number,
    object: StoredObject,
  ): Promise<string> {
    if (!Number.isSafeInteger(sequence) || sequence < 1) throw new TypeError("Run artifact sequence must be a positive integer");
    return this.#transaction(async (client) => {
      const artifactId = await this.#saveArtifact(client, orgId, kind, object);
      const linked = await client.query(
        `INSERT INTO signalbox_architecture.run_artifact (run_id,kind,sequence,artifact_id)
         SELECT $1,$2,$3,$4
         WHERE EXISTS (SELECT 1 FROM signalbox_architecture.agent_run WHERE id=$1 AND org_id=$5)`,
        [runId, kind, sequence, artifactId, orgId],
      );
      if (linked.rowCount !== 1) throw new Error("Run artifact did not match one run");
      return artifactId;
    });
  }

  async #saveArtifact(client: PoolClient, orgId: string, kind: ArtifactKind, object: StoredObject): Promise<string> {
    const id = randomUUID();
    const result = await client.query<{ id: string }>(
      `INSERT INTO signalbox_architecture.object_artifact
        (id,org_id,kind,object_key,sha256,size_bytes,content_type)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (org_id,kind,sha256) DO UPDATE SET object_key=EXCLUDED.object_key
       RETURNING id`,
      [id, orgId, kind, object.key, object.sha256, object.sizeBytes, object.contentType],
    );
    return result.rows[0]!.id;
  }


  async #transaction<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await operation(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}

export class MissingPreparationError extends Error {
  readonly outcome = "MISSING_PREPARATION" as const;
  readonly instruction = "STOP_AND_REPORT" as const;

  constructor(readonly operationIds: readonly string[]) {
    super(`Run manifest contains unavailable operations: ${operationIds.join(", ")}`);
  }
}

export class RunTransitionConflictError extends Error {
  constructor(readonly currentState: RunState, readonly currentVersion: number) {
    super(`Agent run changed concurrently to ${currentState} at version ${currentVersion}`);
  }
}
function governanceBundleRecord(row: Record<string, unknown>): GovernanceBundleRecord {
  const status = String(row.status);
  if (status !== "COMPILED" && status !== "ACTIVE" && status !== "RETIRED") throw new Error(`Unknown governance bundle status '${status}'`);
  const timestamp = (value: unknown): string | null => value === null || value === undefined
    ? null
    : (value instanceof Date ? value : new Date(String(value))).toISOString();
  return {
    id: String(row.id),
    orgId: String(row.org_id),
    status,
    model: {
      name: String(row.model_name),
      version: String(row.model_version),
      sourceHash: String(row.source_hash),
    },
    bundleHash: String(row.bundle_hash),
    sourceObjectKey: String(row.source_object_key),
    bundleObjectKey: String(row.bundle_object_key),
    previousBundleId: row.previous_bundle_id === null ? null : String(row.previous_bundle_id),
    createdBy: String(row.created_by),
    createdAt: timestamp(row.created_at)!,
    activatedBy: row.activated_by === null ? null : String(row.activated_by),
    activatedAt: timestamp(row.activated_at),
  };
}
