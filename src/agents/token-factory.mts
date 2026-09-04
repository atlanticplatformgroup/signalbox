import { setTimeout as delay } from "node:timers/promises";
import { arrayValue, jsonValue, objectValue, optionalString, stringValue } from "./validation.mjs";

export type NemotronRole = "planner" | "operator" | "correction" | "narration";
export type NemotronTier = "ultra" | "super" | "nano";

export interface NemotronModels {
  readonly ultra: string;
  readonly super: string;
  readonly nano: string;
}

export interface ChatTool {
  readonly type: "function";
  readonly function: {
    readonly name: string;
    readonly description: string;
    readonly parameters: Readonly<Record<string, unknown>>;
    readonly strict?: boolean;
  };
}

export interface ChatToolCall {
  readonly id: string;
  readonly type: "function";
  readonly function: {
    readonly name: string;
    readonly arguments: string;
  };
}

export interface ChatMessage {
  readonly role: "system" | "user" | "assistant" | "tool";
  readonly content: string | null;
  readonly tool_call_id?: string;
  readonly tool_calls?: readonly ChatToolCall[];
}

export interface ChatReply {
  readonly model: string;
  readonly message: ChatMessage;
  readonly finishReason: string | null;
}

export interface ChatRequest {
  readonly role: NemotronRole;
  readonly messages: readonly ChatMessage[];
  readonly tools?: readonly ChatTool[];
  readonly toolChoice?: "auto" | "required" | "none" | { readonly type: "function"; readonly function: { readonly name: string } };
  readonly maxCompletionTokens?: number;
  readonly temperature?: number;
  readonly reasoningEffort?: "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
}

export interface StructuredToolRequest {
  readonly role: NemotronRole;
  readonly messages: readonly ChatMessage[];
  readonly name: string;
  readonly description: string;
  readonly parameters: Readonly<Record<string, unknown>>;
  readonly maxCompletionTokens?: number;
  readonly reasoningEffort?: ChatRequest["reasoningEffort"];
}

export interface TokenFactoryClientOptions {
  readonly apiKey: string;
  readonly projectId?: string;
  readonly baseUrl?: string;
  readonly fetch?: typeof fetch;
  readonly requestTimeoutMs?: number;
  readonly maxAttempts?: number;
}

const roleTiers: Readonly<Record<NemotronRole, NemotronTier>> = {
  planner: "ultra",
  operator: "super",
  correction: "nano",
  narration: "super",
};

export class TokenFactoryClient {
  readonly #apiKey: string;
  readonly #projectId?: string;
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #requestTimeoutMs: number;
  readonly #maxAttempts: number;
  #models?: NemotronModels;

  constructor(options: TokenFactoryClientOptions) {
    if (!options.apiKey) throw new Error("Token Factory API key is required");
    this.#apiKey = options.apiKey;
    this.#projectId = options.projectId;
    this.#baseUrl = normalizeBaseUrl(options.baseUrl ?? "https://api.tokenfactory.nebius.com/v1");
    this.#fetch = options.fetch ?? fetch;
    this.#requestTimeoutMs = boundedInteger(options.requestTimeoutMs ?? 60_000, 1_000, 300_000, "requestTimeoutMs");
    this.#maxAttempts = boundedInteger(options.maxAttempts ?? 3, 1, 5, "maxAttempts");
  }

  async discoverModels(): Promise<NemotronModels> {
    if (this.#models) return this.#models;
    const query = this.#projectId
      ? `models?verbose=true&ai_project_id=${encodeURIComponent(this.#projectId)}`
      : "models?verbose=true";
    const response = await this.#request(query, { method: "GET" });
    const root = objectValue(await response.json(), "Token Factory model list");
    const rows = arrayValue(root.data, "Token Factory model list.data");
    const ids = rows.flatMap((row, index) => {
      const model = objectValue(row, `Token Factory model list.data[${index}]`);
      const id = stringValue(model.id, `Token Factory model list.data[${index}].id`);
      const status = optionalString(model.status, `Token Factory model list.data[${index}].status`)?.toLowerCase();
      return status !== undefined && status !== "active" ? [] : [id];
    });
    this.#models = {
      ultra: selectModel(ids, "ultra"),
      super: selectModel(ids, "super"),
      nano: selectModel(ids, "nano"),
    };
    return this.#models;
  }

  async modelFor(role: NemotronRole): Promise<string> {
    return (await this.discoverModels())[roleTiers[role]];
  }

  async chat(request: ChatRequest): Promise<ChatReply> {
    if (request.messages.length === 0) throw new Error("chat messages must not be empty");
    const model = await this.modelFor(request.role);
    const query = this.#projectId ? `chat/completions?ai_project_id=${encodeURIComponent(this.#projectId)}` : "chat/completions";
    const response = await this.#request(query, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        model,
        messages: request.messages,
        tools: request.tools,
        tool_choice: request.toolChoice === "required" ? "auto" : request.toolChoice,
        max_tokens: request.maxCompletionTokens ?? 4_096,
        temperature: request.temperature ?? 0,
        reasoning_effort: request.reasoningEffort,
        stream: false,
      }),
    });
    return parseChatReply(await response.json(), model);
  }

  async structuredTool(request: StructuredToolRequest): Promise<Record<string, unknown>> {
    let messages = request.messages;
    for (let attempt = 1; attempt <= 2; attempt += 1) {
      const reply = await this.chat({
        role: request.role,
        messages,
        tools: [{
          type: "function",
          function: {
            name: request.name,
            description: request.description,
            parameters: request.parameters,
            strict: true,
          },
        }],
        toolChoice: { type: "function", function: { name: request.name } },
        maxCompletionTokens: request.maxCompletionTokens,
        reasoningEffort: request.reasoningEffort,
      });
      const calls = reply.message.tool_calls ?? [];
      let correction = `Call the required '${request.name}' tool exactly once. Return no prose.`;
      if (calls.length === 1 && calls[0]?.function.name === request.name) {
        try {
          return objectValue(jsonValue(calls[0].function.arguments, `${request.name} arguments`), `${request.name} arguments`);
        } catch (error) {
          if (attempt === 2) throw error;
          correction = `Call the required '${request.name}' tool exactly once with complete, valid JSON arguments. Return no prose.`;
        }
      } else if (attempt === 2) {
        throw new Error(`Token Factory model did not call required tool '${request.name}' exactly once`);
      }
      messages = [...messages, { role: "user", content: correction }];
    }
    throw new Error(`Token Factory model did not call required tool '${request.name}' exactly once`);
  }

  async #request(path: string, init: RequestInit): Promise<Response> {
    for (let attempt = 1; attempt <= this.#maxAttempts; attempt += 1) {
      const response = await this.#requestOnce(path, init);
      if (response.ok) return response;
      const retryable = response.status === 429 || response.status >= 500;
      if (!retryable || attempt === this.#maxAttempts) {
        const detail = (await response.text()).slice(0, 2_000);
        throw new Error(`Token Factory request failed (${response.status}): ${detail || response.statusText}`);
      }
      await delay(retryDelayMs(response, attempt));
    }
    throw new Error("Token Factory request exhausted retries");
  }

  async #requestOnce(path: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#requestTimeoutMs);
    try {
      const headers = new Headers(init.headers);
      headers.set("authorization", `Bearer ${this.#apiKey}`);
      headers.set("accept", "application/json");
      return await this.#fetch(`${this.#baseUrl}/${path}`, { ...init, headers, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
  }
}

function parseChatReply(value: unknown, requestedModel: string): ChatReply {
  const root = objectValue(value, "Token Factory chat completion");
  const choices = arrayValue(root.choices, "Token Factory chat completion.choices");
  if (choices.length !== 1) throw new Error("Token Factory chat completion must contain exactly one choice");
  const choice = objectValue(choices[0], "Token Factory chat completion.choices[0]");
  const message = objectValue(choice.message, "Token Factory chat completion.choices[0].message");
  const role = stringValue(message.role, "Token Factory chat completion message.role");
  if (role !== "assistant") throw new Error("Token Factory chat completion message must have assistant role");
  const content = message.content === null || message.content === undefined || message.content === ""
    ? null
    : stringValue(message.content, "Token Factory chat completion message.content");
  const calls = message.tool_calls === undefined ? undefined : parseToolCalls(message.tool_calls);
  const finishReason = choice.finish_reason === null || choice.finish_reason === undefined
    ? null
    : stringValue(choice.finish_reason, "Token Factory chat completion finish_reason");
  return {
    model: optionalString(root.model, "Token Factory chat completion.model") ?? requestedModel,
    message: { role: "assistant", content, ...(calls ? { tool_calls: calls } : {}) },
    finishReason,
  };
}

function parseToolCalls(value: unknown): ChatToolCall[] {
  return arrayValue(value, "Token Factory tool calls").map((candidate, index) => {
    const call = objectValue(candidate, `Token Factory tool calls[${index}]`);
    const type = stringValue(call.type, `Token Factory tool calls[${index}].type`);
    if (type !== "function") throw new Error(`Token Factory tool calls[${index}].type must be function`);
    const fn = objectValue(call.function, `Token Factory tool calls[${index}].function`);
    return {
      id: stringValue(call.id, `Token Factory tool calls[${index}].id`),
      type: "function",
      function: {
        name: stringValue(fn.name, `Token Factory tool calls[${index}].function.name`),
        arguments: stringValue(fn.arguments, `Token Factory tool calls[${index}].function.arguments`),
      },
    };
  });
}

function selectModel(ids: readonly string[], tier: NemotronTier): string {
  const candidates = ids.filter((id) => {
    const normalized = id.toLowerCase();
    return normalized.includes("nemotron") && normalized.includes(tier);
  });
  if (candidates.length === 0) throw new Error(`No active Nemotron ${tier} model was returned by Token Factory`);
  return [...candidates].sort((left, right) => modelRank(left, tier) - modelRank(right, tier) || left.localeCompare(right))[0]!;
}

function modelRank(id: string, tier: NemotronTier): number {
  const normalized = id.toLowerCase();
  let rank = normalized.includes(`nemotron-3-${tier}`) ? 0 : 10;
  if (tier === "nano" && normalized.includes("omni")) rank += 2;
  return rank;
}

function normalizeBaseUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:" && url.hostname !== "127.0.0.1" && url.hostname !== "localhost") {
    throw new Error("Token Factory baseUrl must use HTTPS except for localhost tests");
  }
  return url.toString().replace(/\/$/, "");
}

function boundedInteger(value: number, minimum: number, maximum: number, name: string): number {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function retryDelayMs(response: Response, attempt: number): number {
  const retryAfter = response.headers.get("retry-after");
  if (retryAfter && /^\d+$/.test(retryAfter)) return Math.min(Number(retryAfter) * 1_000, 10_000);
  return Math.min(250 * 2 ** (attempt - 1), 2_000);
}
