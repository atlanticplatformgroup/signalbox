import type {
  CapabilityBindingState,
  CapabilityReadiness,
  GovernanceBundle,
  GovernanceOperation,
  MissingPreparationOutcome,
  ReadinessCode,
  ReadinessDetail,
} from "./contracts.mjs";

const checks: readonly {
  readonly field: keyof Omit<CapabilityBindingState, "operationId" | "details">;
  readonly code: ReadinessCode;
  readonly message: string;
}[] = [
  { field: "runtimeSupported", code: "RUNTIME_UNSUPPORTED", message: "The active Signalbox runtime does not support this operation contract." },
  { field: "resourceBound", code: "RESOURCE_UNBOUND", message: "The operation has no bound governed resource." },
  { field: "connectorBound", code: "CONNECTOR_UNBOUND", message: "The operation has no connector implementation binding." },
  { field: "connectorActive", code: "CONNECTOR_INACTIVE", message: "The bound connector is not active." },
  { field: "credentialReady", code: "CREDENTIAL_UNAVAILABLE", message: "The bound connector has no usable credential lease." },
  { field: "executionProfileReady", code: "EXECUTION_PROFILE_UNAVAILABLE", message: "No compatible active execution profile is available." },
  { field: "delegationActive", code: "DELEGATION_INACTIVE", message: "The agent has no active delegation for this operation and resource." },
  { field: "quotaAvailable", code: "QUOTA_EXHAUSTED", message: "The organization has no remaining run or effect quota." },
  { field: "policyDiscoverable", code: "POLICY_UNDISCOVERABLE", message: "Current policy does not permit this operation to be advertised to the agent." },
];

export function resolveCapabilityReadiness(
  operation: GovernanceOperation,
  state: CapabilityBindingState | undefined,
  checkedAt = new Date().toISOString(),
): CapabilityReadiness {
  if (!state) {
    return {
      operationId: operation.operationId,
      ready: false,
      checkedAt,
      missing: [{ code: "RESOURCE_UNBOUND", message: "The operation has not been resolved against organization bindings." }],
    };
  }
  if (state.operationId !== operation.operationId) throw new TypeError("Capability binding operation does not match the operation contract");
  const supplied = new Map((state.details ?? []).map((detail) => [detail.code, detail]));
  const missing = checks.flatMap((check): ReadinessDetail[] => state[check.field]
    ? []
    : [supplied.get(check.code) ?? { code: check.code, message: check.message }]);
  return { operationId: operation.operationId, ready: missing.length === 0, missing, checkedAt };
}

export function resolveBundleReadiness(
  bundle: GovernanceBundle,
  states: readonly CapabilityBindingState[],
  checkedAt = new Date().toISOString(),
): readonly CapabilityReadiness[] {
  const byOperation = new Map(states.map((state) => [state.operationId, state]));
  return bundle.operations.map((operation) => resolveCapabilityReadiness(operation, byOperation.get(operation.operationId), checkedAt));
}

export function closedOperations(
  bundle: GovernanceBundle,
  states: readonly CapabilityBindingState[],
  checkedAt = new Date().toISOString(),
): { readonly operations: readonly GovernanceOperation[]; readonly readiness: readonly CapabilityReadiness[] } {
  const readiness = resolveBundleReadiness(bundle, states, checkedAt);
  const readyIds = new Set(readiness.filter((item) => item.ready).map((item) => item.operationId));
  return { operations: bundle.operations.filter((operation) => readyIds.has(operation.operationId)), readiness };
}

export function missingPreparation(
  readiness: readonly CapabilityReadiness[],
  operationId?: string,
): MissingPreparationOutcome | null {
  const selected = operationId === undefined ? readiness : readiness.filter((item) => item.operationId === operationId);
  const missing = selected.flatMap((item) => item.missing);
  if (missing.length === 0) return null;
  return { outcome: "MISSING_PREPARATION", operationId, missing, instruction: "STOP_AND_REPORT" };
}
