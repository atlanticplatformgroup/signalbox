import { AgentDeadlineExceededError, type GovernedAgentResult, type AgentLifecycleObserver, type AgentLifecycleStage } from "../agents/runtime.mjs";
import type { SandboxOperationEvent, SandboxOperationObserver, SandboxResult } from "../agents/sandbox.mjs";
import { ArchitectureRepository, type DurableRun, type RunState } from "./repository.mjs";
import type { ObjectArtifactStore } from "./object-store.mjs";

export interface GovernedAgentExecutor {
  run(task: string): Promise<GovernedAgentResult>;
}

export interface DurableAgentContext {
  readonly runId: string;
  readonly lifecycle: AgentLifecycleObserver;
  readonly sandboxOperations: SandboxOperationObserver;
}

export type DurableAgentFactory = (context: DurableAgentContext) => GovernedAgentExecutor | Promise<GovernedAgentExecutor>;

export class DurableAgentOrchestrator {
  constructor(
    private readonly repository: ArchitectureRepository,
    private readonly provider: string,
    private readonly objectStore: ObjectArtifactStore,
  ) {
    if (!provider) throw new TypeError("Sandbox provider is required");
  }

  async execute(orgId: string, claimedRun: DurableRun, task: string, createAgent: DurableAgentFactory): Promise<GovernedAgentResult> {
    if (claimedRun.state !== "RESOLVING") throw new TypeError("Durable execution requires a claimed run in RESOLVING state");
    let current = claimedRun;
    const transition = async (
      nextState: RunState,
      evidence: Readonly<Record<string, unknown>>,
      failure?: { readonly code: string; readonly detail: string },
    ): Promise<void> => {
      current = await this.repository.transitionRun(orgId, current.id, current.state, current.stateVersion, nextState, evidence, failure);
    };
    const lifecycle: AgentLifecycleObserver = {
      transition: async (stage: AgentLifecycleStage, evidence) => {
        await transition(stage, evidence);
      },
    };
    const sandboxOperations = new RepositorySandboxObserver(this.repository, claimedRun.id, this.provider);

    try {
      await transition("PREPARING_ENVIRONMENT", { manifestId: claimedRun.manifestId });
      const agent = await createAgent({ runId: claimedRun.id, lifecycle, sandboxOperations });
      const result = await agent.run(task);
      if (result.runId !== claimedRun.id) throw new Error("Agent result run ID does not match the durable run");
      if (current.state !== "VERIFYING") throw new Error(`Agent completed from unexpected durable state ${current.state}`);
      const [diffObject, logObject] = await Promise.all([
        this.objectStore.put(orgId, "DIFF", new TextEncoder().encode(result.diff), "text/x-diff; charset=utf-8"),
        this.objectStore.put(orgId, "LOG", new TextEncoder().encode(JSON.stringify(result.timeline)), "application/json"),
      ]);
      const [diffArtifactId, logArtifactId] = await Promise.all([
        this.repository.saveRunArtifact(orgId, claimedRun.id, "DIFF", 1, diffObject),
        this.repository.saveRunArtifact(orgId, claimedRun.id, "LOG", 1, logObject),
      ]);
      await transition("COMPLETED", {
        summary: result.summary,
        timelineEntries: result.timeline.length,
        diffArtifactId,
        logArtifactId,
      });
      return result;
    } catch (error) {
      const failureState = failureStateFor(current.state, error);
      if (failureState) {
        const failure = normalizeError(error);
        try {
          await transition(failureState, { error: failure.detail }, failure);
        } catch (transitionError) {
          throw new AggregateError([error, transitionError], "Agent execution and durable failure transition both failed");
        }
      }
      throw error;
    }
  }
}

class RepositorySandboxObserver implements SandboxOperationObserver {
  constructor(
    private readonly repository: ArchitectureRepository,
    private readonly runId: string,
    private readonly provider: string,
  ) {}

  async started(event: SandboxOperationEvent): Promise<void> {
    await this.repository.startSandboxOperation({
      runId: this.runId,
      sequence: event.sequence,
      provider: this.provider,
      operationId: event.operationId,
      inputImage: event.command.image,
    });
  }

  async completed(event: SandboxOperationEvent, result: SandboxResult): Promise<void> {
    await this.repository.completeSandboxOperation({
      runId: this.runId,
      sequence: event.sequence,
      provider: this.provider,
      operationId: event.operationId,
      inputImage: event.command.image,
      resultImage: result.resultImage ?? null,
      state: result.timedOut ? "TIMED_OUT" : result.resultImage ? "SUCCEEDED" : "UNKNOWN",
      exitCode: result.exitCode,
      timedOut: result.timedOut,
    });
  }

  async failed(event: SandboxOperationEvent): Promise<void> {
    await this.repository.completeSandboxOperation({
      runId: this.runId,
      sequence: event.sequence,
      provider: this.provider,
      operationId: event.operationId,
      inputImage: event.command.image,
      resultImage: null,
      state: "UNKNOWN",
      exitCode: null,
      timedOut: null,
    });
  }
}

function failureStateFor(state: RunState, error: unknown): "PREPARATION_FAILED" | "FAILED" | "TIMED_OUT" | null {
  if (error instanceof AgentDeadlineExceededError) return "TIMED_OUT";
  if (state === "RESOLVING" || state === "PREPARING_ENVIRONMENT") return "PREPARATION_FAILED";
  if (state === "PLANNING" || state === "OPERATING" || state === "VERIFYING") return "FAILED";
  return null;
}

function normalizeError(error: unknown): { code: string; detail: string } {
  if (error instanceof Error) return { code: error.name || "AGENT_EXECUTION_FAILED", detail: error.message.slice(0, 4_000) };
  return { code: "AGENT_EXECUTION_FAILED", detail: String(error).slice(0, 4_000) };
}
