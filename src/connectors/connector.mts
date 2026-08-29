export type ExecutionRequestKind = "ISSUE" | "PULL_REQUEST" | "DEPLOYMENT" | "SCHEMA_MIGRATION";
export type ConnectorKind = "GITHUB" | "STATIC_SITE" | "POSTGRESQL";

export interface ExecutionClaim {
  readonly executionId: string;
  readonly claimToken: string;
  readonly attemptCount: number;
  readonly requestKind: ExecutionRequestKind;
  readonly connectorId: string;
  readonly connectorKind: ConnectorKind;
  readonly payload: Readonly<Record<string, unknown>>;
  readonly correlationId: string;
  readonly causationId?: string;
}

export interface ExecutionConnector {
  readonly kind: ConnectorKind;
  execute(claim: ExecutionClaim, signal: AbortSignal): Promise<string>;
  recover?(claim: ExecutionClaim, signal: AbortSignal): Promise<string | undefined>;
}

export class ConnectorFailure extends Error {
  constructor(
    readonly code: string,
    readonly retryable: boolean,
    options?: ErrorOptions,
  ) {
    super(code, options);
    this.name = "ConnectorFailure";
  }
}

export function requireString(payload: Readonly<Record<string, unknown>>, name: string): string {
  const value = payload[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new ConnectorFailure("INVALID_PAYLOAD", false);
  }
  return value;
}

export function throwIfAborted(signal: AbortSignal): void {
  if (signal.aborted) throw new ConnectorFailure("CONNECTOR_TIMEOUT", true, { cause: signal.reason });
}
