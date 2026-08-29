import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import type { ChatTool } from "./token-factory.mjs";
import { arrayValue, jsonValue, objectValue, optionalString, stringValue } from "./validation.mjs";

const publicTraceToolName = "modellang_public_decision_trace";
const operationMetadataKey = "dev.modellang/operationId";
const idempotencyMetadataKey = "dev.modellang/idempotencyKey";
const correlationMetadataKey = "dev.modellang/correlationId";
const causationMetadataKey = "dev.modellang/causationId";

export const defaultGovernedActions = [
  "requestPullRequest",
  "requestStagingDeployment",
  "requestProductionDeployment",
] as const;

export interface McpToolConnection {
  listTools(): Promise<unknown>;
  callTool(request: Readonly<Record<string, unknown>>): Promise<unknown>;
  close(): Promise<void>;
}

export interface GovernedActionDefinition {
  readonly name: string;
  readonly authoredName: string;
  readonly mcpName: string;
  readonly operationId: string;
  readonly description: string;
  readonly inputSchema: Readonly<Record<string, unknown>>;
}

export interface GovernanceDenial {
  readonly kind: "signalboxGovernanceDenial";
  readonly source: "modellangPublicDecisionTrace" | "modellangExecutionError";
  readonly operationId: string;
  readonly policyBoundaryId: string;
  readonly policyId: null;
  readonly policyDisclosure: "withheldByPublicTrace";
  readonly ruleId: string | null;
  readonly status: string;
  readonly traceId?: string;
  readonly decisionEvidence: Readonly<Record<string, unknown>>;
}

export interface GovernanceExecutionMetadata {
  readonly idempotencyKey: string;
  readonly correlationId: string;
  readonly causationId?: string;
}

export type GovernanceInvocation =
  | { readonly outcome: "executed"; readonly action: GovernedActionDefinition; readonly result: unknown; readonly trace: Readonly<Record<string, unknown>> }
  | { readonly outcome: "denied"; readonly action: GovernedActionDefinition; readonly denial: GovernanceDenial };

export interface GovernanceToolPort {
  definitions(): Promise<readonly GovernedActionDefinition[]>;
  modelTools(): Promise<readonly ChatTool[]>;
  invoke(authoredName: string, input: Readonly<Record<string, unknown>>, metadata: GovernanceExecutionMetadata): Promise<GovernanceInvocation>;
}

export interface SignalboxMcpToolsOptions {
  readonly connection: McpToolConnection;
  readonly allowedActions?: readonly string[];
}

export class SignalboxMcpTools implements GovernanceToolPort {
  readonly #connection: McpToolConnection;
  readonly #allowedActions: ReadonlySet<string>;
  #definitions?: readonly GovernedActionDefinition[];

  constructor(options: SignalboxMcpToolsOptions) {
    this.#connection = options.connection;
    this.#allowedActions = new Set(options.allowedActions ?? defaultGovernedActions);
    if (this.#allowedActions.size === 0) throw new Error("At least one governed Signalbox action is required");
  }

  static async connect(options: {
    readonly url: string;
    readonly accessToken: string;
    readonly allowedActions?: readonly string[];
  }): Promise<SignalboxMcpTools> {
    if (!options.accessToken) throw new Error("Signalbox MCP access token is required");
    const client = new Client({ name: "signalbox-agent", version: "0.0.1" });
    const transport = new StreamableHTTPClientTransport(new URL(options.url), {
      authProvider: { token: async () => options.accessToken },
    });
    await client.connect(transport);
    return new SignalboxMcpTools({ connection: client, allowedActions: options.allowedActions });
  }

  async definitions(): Promise<readonly GovernedActionDefinition[]> {
    if (this.#definitions) return this.#definitions;
    const response = objectValue(await this.#connection.listTools(), "Signalbox MCP tools response");
    const tools = arrayValue(response.tools, "Signalbox MCP tools response.tools");
    const definitions: GovernedActionDefinition[] = [];
    for (const [index, candidate] of tools.entries()) {
      const tool = objectValue(candidate, `Signalbox MCP tools[${index}]`);
      const title = optionalString(tool.title, `Signalbox MCP tools[${index}].title`);
      if (!title || !this.#allowedActions.has(title)) continue;
      const meta = objectValue(tool._meta, `Signalbox MCP tools[${index}]._meta`);
      const operationId = stringValue(meta[operationMetadataKey], `Signalbox MCP tools[${index}] operation ID`);
      if (!operationId.startsWith("action:")) throw new Error(`Signalbox MCP tool '${title}' is not an action`);
      definitions.push({
        name: `signalbox_${title}`,
        authoredName: title,
        mcpName: stringValue(tool.name, `Signalbox MCP tools[${index}].name`),
        operationId,
        description: stringValue(tool.description, `Signalbox MCP tools[${index}].description`),
        inputSchema: objectValue(tool.inputSchema, `Signalbox MCP tools[${index}].inputSchema`),
      });
    }
    const missing = [...this.#allowedActions].filter((name) => !definitions.some((definition) => definition.authoredName === name));
    if (missing.length > 0) throw new Error(`Signalbox MCP did not advertise allowed actions: ${missing.join(", ")}`);
    this.#definitions = definitions.sort((left, right) => left.authoredName.localeCompare(right.authoredName));
    return this.#definitions;
  }

  async modelTools(): Promise<readonly ChatTool[]> {
    return (await this.definitions()).map((definition) => ({
      type: "function",
      function: {
        name: definition.name,
        description: `${definition.description} Signalbox assesses current authorization immediately before execution.`,
        parameters: definition.inputSchema,
        strict: true,
      },
    }));
  }

  async invoke(authoredName: string, input: Readonly<Record<string, unknown>>, metadata: GovernanceExecutionMetadata): Promise<GovernanceInvocation> {
    validateCommandMetadata(metadata);
    const action = (await this.definitions()).find((definition) => definition.authoredName === authoredName);
    if (!action) throw new Error(`Signalbox action '${authoredName}' is not allowed`);
    const traceResult = objectValue(await this.#connection.callTool({
      name: publicTraceToolName,
      arguments: { action: { operationId: action.operationId, input } },
    }), "Signalbox MCP trace result");
    if (traceResult.isError === true) throw new Error(`Signalbox applicability trace failed: ${toolErrorMessage(traceResult)}`);
    const trace = objectValue(traceResult.structuredContent, "Signalbox public decision trace");
    const decision = objectValue(trace.decision, "Signalbox public decision trace.decision");
    if (decision.applicable !== true) {
      return { outcome: "denied", action, denial: denialFromTrace(action, trace, decision) };
    }

    const commandMeta: Record<string, unknown> = {
      [idempotencyMetadataKey]: metadata.idempotencyKey,
      [correlationMetadataKey]: metadata.correlationId,
      ...(metadata.causationId ? { [causationMetadataKey]: metadata.causationId } : {}),
    };
    const execution = objectValue(await this.#connection.callTool({
      name: action.mcpName,
      arguments: input,
      _meta: commandMeta,
    }), "Signalbox MCP execution result");
    if (execution.isError === true) {
      return {
        outcome: "denied",
        action,
        denial: denialFromExecution(action, trace, execution),
      };
    }
    return { outcome: "executed", action, result: execution.structuredContent, trace };
  }

  async close(): Promise<void> {
    await this.#connection.close();
  }
}

function denialFromTrace(
  action: GovernedActionDefinition,
  trace: Record<string, unknown>,
  decision: Record<string, unknown>,
): GovernanceDenial {
  const explanation = objectValue(decision.explanation, "Signalbox public decision trace.decision.explanation");
  return {
    kind: "signalboxGovernanceDenial",
    source: "modellangPublicDecisionTrace",
    operationId: action.operationId,
    policyBoundaryId: action.operationId,
    policyId: null,
    policyDisclosure: "withheldByPublicTrace",
    ruleId: stringValue(explanation.ruleId, "Signalbox public decision trace ruleId"),
    status: stringValue(decision.status, "Signalbox public decision trace status"),
    traceId: optionalString(trace.traceId, "Signalbox public decision trace.traceId"),
    decisionEvidence: {
      model: trace.model,
      decision,
      stages: trace.stages,
      closure: trace.closure,
      freshness: trace.freshness,
    },
  };
}

function denialFromExecution(
  action: GovernedActionDefinition,
  trace: Record<string, unknown>,
  execution: Record<string, unknown>,
): GovernanceDenial {
  const body = toolErrorBody(execution);
  return {
    kind: "signalboxGovernanceDenial",
    source: "modellangExecutionError",
    operationId: action.operationId,
    policyBoundaryId: action.operationId,
    policyId: null,
    policyDisclosure: "withheldByPublicTrace",
    ruleId: optionalString(body.ruleId, "Signalbox execution error ruleId") ?? null,
    status: optionalString(body.code, "Signalbox execution error code") ?? "ML_TOOL_EXECUTION",
    traceId: optionalString(trace.traceId, "Signalbox public decision trace.traceId"),
    decisionEvidence: {
      model: trace.model,
      applicability: trace.decision,
      stages: trace.stages,
      closure: trace.closure,
      executionError: body,
    },
  };
}

function toolErrorBody(result: Record<string, unknown>): Record<string, unknown> {
  const content = arrayValue(result.content, "Signalbox MCP error content");
  for (const candidate of content) {
    const item = objectValue(candidate, "Signalbox MCP error content item");
    if (item.type === "text" && typeof item.text === "string") {
      const parsed = jsonValue(item.text, "Signalbox MCP error text");
      return objectValue(parsed, "Signalbox MCP error body");
    }
  }
  return { error: "Signalbox MCP tool execution failed" };
}

function toolErrorMessage(result: Record<string, unknown>): string {
  const body = toolErrorBody(result);
  return optionalString(body.error, "Signalbox MCP error") ?? JSON.stringify(body);
}

function validateCommandMetadata(metadata: GovernanceExecutionMetadata): void {
  const pattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
  if (!pattern.test(metadata.idempotencyKey)) throw new Error("Signalbox idempotency key is invalid");
  if (!pattern.test(metadata.correlationId)) throw new Error("Signalbox correlation ID is invalid");
  if (metadata.causationId && !pattern.test(metadata.causationId)) throw new Error("Signalbox causation ID is invalid");
}
