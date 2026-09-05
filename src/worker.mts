import type { Pool, PoolClient } from "pg";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import {
  ConnectorFailure,
  type ConnectorKind,
  type ExecutionClaim,
  type ExecutionConnector,
  type ExecutionRequestKind,
} from "./connectors/connector.mjs";

const COMPLETE_EXECUTION = "action:act_5be24324b68d4c2eb334732b36e1b16c";
const FAIL_EXECUTION = "action:act_926686163a6544e79d44dea9336d2c88";

export interface WorkerIdentity {
  readonly issuer: string;
  readonly subject: string;
}

export interface SignalboxWorkerOptions {
  readonly pool: Pool;
  readonly identity: WorkerIdentity;
  readonly workerId: string;
  readonly connectors: ReadonlyMap<string, ExecutionConnector>;
  readonly leaseSeconds?: number;
  readonly connectorTimeoutMs?: number;
  readonly maxAttempts?: number;
  readonly retryBaseMs?: number;
  readonly retryMaxMs?: number;
}

interface ClaimRow {
  readonly execution_id: string;
  readonly claim_token: string;
  readonly attempt_count: number;
  readonly last_error_code: string | null;
  readonly effect_reference: string | null;
  readonly request_kind: ExecutionRequestKind;
  readonly connector_id: string;
  readonly connector_kind: ConnectorKind;
  readonly payload: Record<string, unknown>;
  readonly correlation_id: string | null;
  readonly causation_id: string | null;
}

export class SignalboxWorker {
  private readonly executor;
  private readonly leaseSeconds: number;
  private readonly connectorTimeoutMs: number;
  private readonly maxAttempts: number;
  private readonly retryBaseMs: number;
  private readonly retryMaxMs: number;

  constructor(private readonly options: SignalboxWorkerOptions) {
    if (!options.workerId || options.workerId.length > 128) throw new Error("workerId must contain 1 to 128 characters");
    this.leaseSeconds = integerInRange(options.leaseSeconds ?? 45, 5, 300, "leaseSeconds");
    this.connectorTimeoutMs = integerInRange(options.connectorTimeoutMs ?? 30_000, 100, 299_000, "connectorTimeoutMs");
    if (this.connectorTimeoutMs + 2_000 >= this.leaseSeconds * 1_000) {
      throw new Error("leaseSeconds must exceed connectorTimeoutMs by at least two seconds");
    }
    this.maxAttempts = integerInRange(options.maxAttempts ?? 5, 1, 20, "maxAttempts");
    this.retryBaseMs = integerInRange(options.retryBaseMs ?? 1_000, 1, 3_600_000, "retryBaseMs");
    this.retryMaxMs = integerInRange(options.retryMaxMs ?? 30_000, this.retryBaseMs, 3_600_000, "retryMaxMs");
    this.executor = createSignalboxGatewayExecutor(options.pool, options.identity);
  }

  async runOnce(): Promise<boolean> {
    const claim = await this.claim();
    if (!claim) return false;

    if (claim.lastErrorCode?.startsWith("TERMINAL_")) {
      await this.failPermanently(claim, claim.lastErrorCode.slice("TERMINAL_".length));
      return true;
    }
    if (claim.effectReference) {
      await this.completeEffect(claim, claim.effectReference);
      return true;
    }

    const connector = this.options.connectors.get(claim.connectorId);
    if (!connector || connector.kind !== claim.connectorKind) {
      await this.failPermanently(claim, "CONNECTOR_NOT_CONFIGURED");
      return true;
    }

    const recoveryOnly = claim.attemptCount > this.maxAttempts || claim.lastErrorCode === "RECOVERY_REQUIRED";
    if (recoveryOnly && !connector.recover) {
      await this.failPermanently(claim, "RETRY_EXHAUSTED");
      return true;
    }
    const controller = new AbortController();
    let timeout: ReturnType<typeof setTimeout> | undefined;
    let connection: PoolClient | undefined;
    let transactionOpen = false;
    let recordingEffect = false;
    let failure: ConnectorFailure | undefined;
    let externalReference: string | undefined;
    try {
      connection = await this.options.pool.connect();
      await connection.query("BEGIN ISOLATION LEVEL READ COMMITTED");
      transactionOpen = true;
      if (await this.confirm(connection, claim)) {
        timeout = setTimeout(() => controller.abort(new Error("connector timeout")), this.connectorTimeoutMs);
        timeout.unref?.();
        externalReference = recoveryOnly
          ? await connector.recover!(claim, controller.signal)
          : await connector.execute(claim, controller.signal);
        if (!externalReference) throw new ConnectorFailure("RETRY_EXHAUSTED", false);
        if (externalReference.length > 2_048) throw new ConnectorFailure("INVALID_EXTERNAL_REFERENCE", false);
        recordingEffect = true;
        if (!await this.recordEffect(connection, claim, externalReference)) {
          throw new ConnectorFailure("EFFECT_RECORDING_FAILED", true);
        }
        await connection.query("COMMIT");
      } else {
        await connection.query("ROLLBACK");
      }
      transactionOpen = false;
    } catch (error) {
      failure = recordingEffect
        ? new ConnectorFailure("RECOVERY_REQUIRED", true, { cause: error })
        : normalizeFailure(error, controller.signal);
      if (transactionOpen && connection) {
        try {
          await connection.query("ROLLBACK");
        } catch {
          connection.release(true);
          connection = undefined;
        }
      }
    } finally {
      clearTimeout(timeout);
      connection?.release();
    }

    if (failure) {
      if (!failure.retryable) {
        await this.failPermanently(claim, failure.code);
      } else if (recoveryOnly && claim.attemptCount >= this.maxAttempts + 2) {
        await this.failPermanently(claim, "OUTCOME_UNKNOWN");
      } else {
        await this.release(
          claim,
          recordingEffect || claim.attemptCount >= this.maxAttempts ? "RECOVERY_REQUIRED" : failure.code,
          retryDelaySeconds(claim.attemptCount, this.retryBaseMs, this.retryMaxMs),
        );
      }
      return true;
    }
    if (!externalReference) {
      await this.finish(claim);
      return true;
    }
    // The policy lock and effect ledger commit together before the terminal action
    // opens its own transaction, so completion cannot deadlock on this worker.
    await this.completeEffect(claim, externalReference);
    return true;
  }

  async runUntilIdle(limit = 100): Promise<number> {
    integerInRange(limit, 1, 10_000, "limit");
    let handled = 0;
    while (handled < limit && await this.runOnce()) handled += 1;
    return handled;
  }

  private async claim(): Promise<(ExecutionClaim & {
    readonly lastErrorCode?: string;
    readonly effectReference?: string;
  }) | undefined> {
    const result = await this.options.pool.query<ClaimRow>(
      `SELECT * FROM model_signalbox_worker.claim_execution($1, $2, $3, $4)`,
      [this.options.identity.issuer, this.options.identity.subject, this.options.workerId, this.leaseSeconds],
    );
    const row = result.rows[0];
    if (!row) return undefined;
    return Object.freeze({
      executionId: row.execution_id,
      claimToken: row.claim_token,
      attemptCount: row.attempt_count,
      lastErrorCode: row.last_error_code ?? undefined,
      effectReference: row.effect_reference ?? undefined,
      requestKind: row.request_kind,
      connectorId: row.connector_id,
      connectorKind: row.connector_kind,
      payload: Object.freeze(row.payload),
      correlationId: row.correlation_id ?? `execution:${row.execution_id}`,
      causationId: row.causation_id ?? undefined,
    });
  }

  private async confirm(connection: PoolClient, claim: ExecutionClaim): Promise<boolean> {
    const result = await connection.query<{ confirmed: boolean }>(
      `SELECT model_signalbox_worker.confirm_execution_claim($1, $2, $3, $4, $5) AS confirmed`,
      [this.options.identity.issuer, this.options.identity.subject, this.options.workerId, claim.executionId, claim.claimToken],
    );
    return result.rows[0]?.confirmed === true;
  }

  private async recordEffect(connection: PoolClient, claim: ExecutionClaim, externalReference: string): Promise<boolean> {
    const result = await connection.query<{ recorded: boolean }>(
      `SELECT model_signalbox_worker.record_execution_effect($1, $2, $3, $4) AS recorded`,
      [this.options.workerId, claim.executionId, claim.claimToken, externalReference],
    );
    return result.rows[0]?.recorded === true;
  }

  private async completeEffect(claim: ExecutionClaim, externalReference: string): Promise<void> {
    if (externalReference.length === 0 || externalReference.length > 2_048) {
      await this.failPermanently(claim, "INVALID_EXTERNAL_REFERENCE");
      return;
    }
    try {
      await this.executor.execute(
        COMPLETE_EXECUTION,
        { execution: claim.executionId, externalReference },
        {
          idempotencyKey: `execution:${claim.executionId}:complete`,
          correlationId: claim.correlationId,
          causationId: claim.causationId ?? claim.executionId,
        },
      );
      await this.finish(claim);
    } catch {
      await this.release(claim, "COMPLETION_FAILED", retryDelaySeconds(
        claim.attemptCount,
        this.retryBaseMs,
        this.retryMaxMs,
      ));
    }
  }

  private async release(claim: ExecutionClaim, code: string, delaySeconds: number): Promise<boolean> {
    const result = await this.options.pool.query<{ released: boolean }>(
      `SELECT model_signalbox_worker.release_execution_claim($1, $2, $3, $4, $5) AS released`,
      [this.options.workerId, claim.executionId, claim.claimToken, safeCode(code), delaySeconds],
    );
    return result.rows[0]?.released === true;
  }

  private async finish(claim: ExecutionClaim): Promise<boolean> {
    const result = await this.options.pool.query<{ finished: boolean }>(
      `SELECT model_signalbox_worker.finish_execution_claim($1, $2, $3) AS finished`,
      [this.options.workerId, claim.executionId, claim.claimToken],
    );
    return result.rows[0]?.finished === true;
  }

  private async failPermanently(claim: ExecutionClaim, rawCode: string): Promise<void> {
    const code = safeCode(rawCode);
    try {
      await this.executor.execute(
        FAIL_EXECUTION,
        { execution: claim.executionId, failureMessage: code },
        {
          idempotencyKey: `execution:${claim.executionId}:fail`,
          correlationId: claim.correlationId,
          causationId: claim.causationId ?? claim.executionId,
        },
      );
      await this.finish(claim);
    } catch (error) {
      try {
        await this.release(claim, safeCode(`TERMINAL_${code}`), retryDelaySeconds(
          claim.attemptCount,
          this.retryBaseMs,
          this.retryMaxMs,
        ));
      } catch (releaseError) {
        throw new AggregateError([error, releaseError], "failed to persist terminal execution state");
      }
    }
  }
}

function integerInRange(value: number, minimum: number, maximum: number, name: string): number {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function normalizeFailure(error: unknown, signal: AbortSignal): ConnectorFailure {
  if (signal.aborted) return new ConnectorFailure("CONNECTOR_TIMEOUT", true, { cause: error });
  if (error instanceof ConnectorFailure) return error;
  return new ConnectorFailure("CONNECTOR_INTERNAL", true, { cause: error });
}

function safeCode(code: string): string {
  const normalized = code.toUpperCase().replace(/[^A-Z0-9_]/g, "_").slice(0, 64);
  return /^[A-Z]/.test(normalized) ? normalized : `E_${normalized}`.slice(0, 64);
}

function retryDelaySeconds(attempt: number, baseMs: number, maximumMs: number): number {
  const delayMs = Math.min(maximumMs, baseMs * (2 ** Math.max(0, attempt - 1)));
  return Math.min(3_600, Math.ceil(delayMs / 1_000));
}
