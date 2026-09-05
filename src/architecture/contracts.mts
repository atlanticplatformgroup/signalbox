import { createHash } from "node:crypto";

export const governanceBundleFormat = "signalbox-governance-bundle/2" as const;
export const runManifestFormat = "signalbox-run-manifest/1" as const;
export const executionProfileFormat = "signalbox-execution-profile/1" as const;

export interface GovernanceOperation {
  readonly operationId: string;
  readonly name: string;
  readonly description: string;
  readonly inputSchema: Readonly<Record<string, unknown>>;
  readonly requiredBindings: readonly BindingKind[];
}

export type BindingKind = "RESOURCE" | "CONNECTOR" | "CREDENTIAL" | "EXECUTION_PROFILE" | "DELEGATION" | "QUOTA";
export interface GovernanceBundlePreview {
  readonly agents: readonly string[];
  readonly connectors: readonly string[];
  readonly resources: readonly string[];
  readonly capabilities: readonly string[];
  readonly delegations: readonly string[];
  readonly approvalBoundaries: readonly string[];
  readonly mcpTools: readonly string[];
}


export interface GovernanceBundle {
  readonly format: typeof governanceBundleFormat;
  readonly model: {
    readonly name: string;
    readonly version: string;
    readonly sourceHash: string;
  };
  readonly compilerVersion: string;
  readonly runtimeCompatibility: string;
  readonly operations: readonly GovernanceOperation[];
  readonly preview: GovernanceBundlePreview;
  readonly decisionGraph: Readonly<Record<string, unknown>>;
  readonly enforcement: {
    readonly decisionSql: string;
    readonly structureHash: string;
  };
  readonly provenance: Readonly<Record<string, unknown>>;
  readonly bundleHash: string;
}

export interface ExecutionProfileConfiguration {
  readonly format: typeof executionProfileFormat;
  readonly provider: string;
  readonly imageDigest: string;
  readonly repositoryStrategy: "BUNDLE" | "AUTHENTICATED_CLONE";
  readonly initialization: readonly {
    readonly executable: string;
    readonly args: readonly string[];
    readonly networking: "DISABLED" | "RESTRICTED_REGISTRIES";
  }[];
  readonly checks: readonly {
    readonly name: string;
    readonly executable: string;
    readonly args: readonly string[];
    readonly timeoutSeconds: number;
  }[];
  readonly egress: {
    readonly initialization: "DISABLED" | "RESTRICTED_REGISTRIES";
    readonly operation: "DISABLED";
  };
  readonly secretRefs: readonly string[];
  readonly limits: {
    readonly maxCommands: number;
    readonly maxWriteBytes: number;
    readonly maxDurationSeconds: number;
  };
}

export interface VersionedExecutionProfile {
  readonly id: string;
  readonly orgId: string;
  readonly name: string;
  readonly version: string;
  readonly configuration: ExecutionProfileConfiguration;
  readonly configurationHash: string;
}

export interface CapabilityBindingState {
  readonly operationId: string;
  readonly runtimeSupported: boolean;
  readonly resourceBound: boolean;
  readonly connectorBound: boolean;
  readonly connectorActive: boolean;
  readonly credentialReady: boolean;
  readonly executionProfileReady: boolean;
  readonly delegationActive: boolean;
  readonly quotaAvailable: boolean;
  readonly policyDiscoverable: boolean;
  readonly details?: readonly ReadinessDetail[];
}

export type ReadinessCode =
  | "RUNTIME_UNSUPPORTED"
  | "RESOURCE_UNBOUND"
  | "CONNECTOR_UNBOUND"
  | "CONNECTOR_INACTIVE"
  | "CREDENTIAL_UNAVAILABLE"
  | "EXECUTION_PROFILE_UNAVAILABLE"
  | "DELEGATION_INACTIVE"
  | "QUOTA_EXHAUSTED"
  | "POLICY_UNDISCOVERABLE";

export interface ReadinessDetail {
  readonly code: ReadinessCode;
  readonly message: string;
  readonly requirement?: string;
}

export interface CapabilityReadiness {
  readonly operationId: string;
  readonly ready: boolean;
  readonly missing: readonly ReadinessDetail[];
  readonly checkedAt: string;
}

export interface RunManifestPins {
  readonly governanceBundle: { readonly id: string; readonly hash: string; readonly sourceHash: string };
  readonly signalboxRuntime: { readonly version: string };
  readonly inferenceModels: {
    readonly planner: string;
    readonly operator: string;
    readonly correction: string;
    readonly narration: string;
  };
  readonly connectorVersions: Readonly<Record<string, string>>;
  readonly executionProfile: { readonly id: string; readonly version: string; readonly configurationHash: string };
  readonly imageDigest: string;
  readonly repository: { readonly source: "BUNDLE" | "AUTHENTICATED_CLONE"; readonly revision: string; readonly contentHash?: string };
  readonly toolCatalogHash: string;
}

export interface RunManifest {
  readonly format: typeof runManifestFormat;
  readonly id: string;
  readonly orgId: string;
  readonly agentId: string;
  readonly task: string;
  readonly pins: RunManifestPins;
  readonly allowedOperationIds: readonly string[];
  readonly allowedChecks: readonly string[];
  readonly budgets: {
    readonly maxOperatorTurns: number;
    readonly maxSandboxCommands: number;
    readonly maxSandboxSeconds: number;
    readonly maxInferenceTokens: number;
    readonly maxExternalEffects: number;
  };
  readonly deadline: string;
  readonly createdAt: string;
  readonly manifestHash: string;
}

export interface MissingPreparationOutcome {
  readonly outcome: "MISSING_PREPARATION";
  readonly operationId?: string;
  readonly missing: readonly ReadinessDetail[];
  readonly instruction: "STOP_AND_REPORT";
}

export function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

export function sha256Json(value: unknown): string {
  return `sha256:${createHash("sha256").update(canonicalJson(value)).digest("hex")}`;
}

export function withBundleHash(bundle: Omit<GovernanceBundle, "bundleHash">): GovernanceBundle {
  return deepFreeze({ ...bundle, bundleHash: sha256Json(bundle) });
}

export function withExecutionProfileHash(profile: Omit<VersionedExecutionProfile, "configurationHash">): VersionedExecutionProfile {
  return deepFreeze({ ...profile, configurationHash: sha256Json(profile.configuration) });
}

export function withManifestHash(manifest: Omit<RunManifest, "manifestHash">): RunManifest {
  validateRunManifest(manifest);
  return deepFreeze({ ...manifest, manifestHash: sha256Json(manifest) });
}

export function verifyRunManifest(value: RunManifest): RunManifest {
  if (!value || typeof value !== "object") throw new TypeError("Run manifest must be an object");
  const { manifestHash, ...unsigned } = value;
  if (!/^sha256:[0-9a-f]{64}$/.test(manifestHash)) throw new TypeError("Run manifest hash must be a SHA-256 digest");
  const verified = withManifestHash(unsigned);
  if (verified.manifestHash !== manifestHash) throw new TypeError("Run manifest hash does not match its immutable content");
  return verified;
}

function validateRunManifest(manifest: Omit<RunManifest, "manifestHash">): void {
  if (manifest.format !== runManifestFormat) throw new TypeError("Unsupported run manifest format");
  if (!manifest.task.trim()) throw new TypeError("Run manifest task is required");
  if (manifest.allowedOperationIds.length !== new Set(manifest.allowedOperationIds).size) throw new TypeError("Run manifest operation IDs must be unique");
  if (manifest.allowedChecks.length !== new Set(manifest.allowedChecks).size) throw new TypeError("Run manifest check names must be unique");
  const deadline = Date.parse(manifest.deadline);
  const createdAt = Date.parse(manifest.createdAt);
  if (!Number.isFinite(deadline) || !Number.isFinite(createdAt) || deadline <= createdAt) throw new TypeError("Run manifest deadline must be after creation");
  for (const [name, value] of Object.entries(manifest.budgets)) {
    if (!Number.isSafeInteger(value) || value < 1) throw new TypeError(`Run manifest budget '${name}' must be a positive integer`);
  }
  const requiredPins = [
    manifest.pins.governanceBundle.id,
    manifest.pins.governanceBundle.hash,
    manifest.pins.governanceBundle.sourceHash,
    manifest.pins.signalboxRuntime.version,
    manifest.pins.inferenceModels.planner,
    manifest.pins.inferenceModels.operator,
    manifest.pins.inferenceModels.correction,
    manifest.pins.inferenceModels.narration,
    manifest.pins.executionProfile.id,
    manifest.pins.executionProfile.version,
    manifest.pins.executionProfile.configurationHash,
    manifest.pins.imageDigest,
    manifest.pins.repository.revision,
    manifest.pins.toolCatalogHash,
  ];
  if (requiredPins.some((value) => !value)) throw new TypeError("Run manifest has an empty immutable pin");
}

function canonicalValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).sort(([left], [right]) => left.localeCompare(right)).map(([key, item]) => [key, canonicalValue(item)]));
  }
  if (typeof value === "number" && !Number.isFinite(value)) throw new TypeError("Canonical JSON cannot contain non-finite numbers");
  if (value === undefined) throw new TypeError("Canonical JSON cannot contain undefined");
  return value;
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const item of Object.values(value as Record<string, unknown>)) deepFreeze(item);
  }
  return value;
}
