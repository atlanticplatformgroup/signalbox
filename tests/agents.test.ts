import { Buffer } from "node:buffer";
import { describe, expect, it } from "vitest";
import { GovernedCodingAgent, type AgentInference } from "../src/agents/runtime.mjs";
import { SandboxWorkspace, TokenFactorySandboxClient, type SandboxResult, type SandboxWorkspacePort } from "../src/agents/sandbox.mjs";
import { SignalboxMcpTools, type McpToolConnection } from "../src/agents/signalbox-mcp.mjs";
import { TokenFactoryClient, type ChatReply, type ChatRequest, type StructuredToolRequest } from "../src/agents/token-factory.mjs";

const productionOperation = "action:act-production";
const stagingOperation = "action:act-staging";
const pullRequestOperation = "action:act-pull-request";

function mcpTool(name: string, title: string, operationId: string): Record<string, unknown> {
  return {
    name,
    title,
    description: `Execute ${title}`,
    inputSchema: { type: "object", additionalProperties: true },
    _meta: { "dev.modellang/operationId": operationId },
  };
}

function trace(operationId: string, applicable: boolean): Record<string, unknown> {
  return {
    traceId: `trace-${operationId.slice(operationId.lastIndexOf("-") + 1)}`,
    operationId,
    model: { id: "model:Signalbox", version: "0.52.0", sourceHash: "sha256:test" },
    freshness: { maxAgeSeconds: 0 },
    decision: {
      operationId,
      status: applicable ? "applicable" : "denied",
      applicable,
      explanation: { kind: "authorization", ruleId: `authorize:${operationId}` },
    },
    stages: { authorization: { ruleId: `authorize:${operationId}`, outcome: applicable ? "passed" : "failed" }, requirements: [], revision: { ruleId: `revision:${operationId}`, outcome: "notRequested" } },
    closure: { currentEvaluation: true, executionObserved: false, durableEvidence: false },
  };
}

class FakeGovernanceConnection implements McpToolConnection {
  readonly calls: Readonly<Record<string, unknown>>[] = [];

  async listTools(): Promise<unknown> {
    return {
      tools: [
        mcpTool("act-production", "requestProductionDeployment", productionOperation),
        mcpTool("act-staging", "requestStagingDeployment", stagingOperation),
        mcpTool("act-pull-request", "requestPullRequest", pullRequestOperation),
      ],
    };
  }

  async callTool(request: Readonly<Record<string, unknown>>): Promise<unknown> {
    (this.calls as Record<string, unknown>[]).push(request);
    if (request.name === "modellang_public_decision_trace") {
      const argumentsValue = request.arguments as { action: { operationId: string } };
      const operationId = argumentsValue.action.operationId;
      return { structuredContent: trace(operationId, operationId !== productionOperation) };
    }
    return { structuredContent: { id: "00000000-0000-4000-8000-000000000099", status: "READY" } };
  }

  async close(): Promise<void> {}
}

describe("Token Factory Nemotron client", () => {
  it("discovers current tier IDs at boot and uses the discovered role model", async () => {
    const requests: { url: string; init: RequestInit }[] = [];
    const fakeFetch = (async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      requests.push({ url, init: init ?? {} });
      if (url.includes("/models?verbose=true")) {
        return Response.json({
          object: "list",
          data: [
            { id: "nvidia/nemotron-3-nano-omni", status: "active" },
            { id: "nvidia/nemotron-3-super-dynamic", status: "active" },
            { id: "nvidia/nemotron-3-ultra-dynamic", status: "active" },
            { id: "nvidia/nemotron-3-nano-30b-dynamic", status: "active" },
            { id: "nvidia/nemotron-2-ultra-retired", status: "deprecated" },
          ],
        });
      }
      const body = JSON.parse(String(init?.body)) as {
        model: string;
        tool_choice: "auto" | { function: { name: string } };
      };
      const toolName = body.tool_choice === "auto" ? "submit" : body.tool_choice.function.name;
      return Response.json({
        model: body.model,
        choices: [{
          finish_reason: "tool_calls",
          message: {
            role: "assistant",
            content: "",
            tool_calls: [{ id: "call-1", type: "function", function: { name: toolName, arguments: "{\"answer\":\"ok\"}" } }],
          },
        }],
      });
    }) as typeof fetch;
    const client = new TokenFactoryClient({
      apiKey: "test-key",
      projectId: "test-project",
      baseUrl: "http://127.0.0.1:9000/v1",
      fetch: fakeFetch,
    });

    expect(await client.discoverModels()).toEqual({
      ultra: "nvidia/nemotron-3-ultra-dynamic",
      super: "nvidia/nemotron-3-super-dynamic",
      nano: "nvidia/nemotron-3-nano-30b-dynamic",
    });
    expect(await client.modelFor("narration")).toBe("nvidia/nemotron-3-super-dynamic");
    const result = await client.structuredTool({
      role: "correction",
      name: "submit",
      description: "submit",
      parameters: { type: "object" },
      messages: [{ role: "user", content: "choose" }],
    });
    expect(result).toEqual({ answer: "ok" });
    await client.chat({
      role: "operator",
      messages: [{ role: "user", content: "inspect" }],
      tools: [],
      toolChoice: "required",
      maxCompletionTokens: 8_192,
    });
    const operatorBody = JSON.parse(String(requests.at(-1)?.init.body)) as Record<string, unknown>;
    expect(operatorBody.tool_choice).toBe("auto");
    expect(operatorBody.max_tokens).toBe(8_192);
    expect(operatorBody).not.toHaveProperty("max_completion_tokens");
    const chatBody = JSON.parse(String(requests.at(-2)?.init.body)) as { model: string };
    expect(chatBody.model).toBe("nvidia/nemotron-3-nano-30b-dynamic");
    expect(new Headers(requests[0]?.init.headers).get("authorization")).toBe("Bearer test-key");
    expect(requests.at(-1)?.url).toContain("ai_project_id=test-project");
  });

  it("retries a required structured tool once after malformed JSON arguments", async () => {
    let completionCount = 0;
    const fakeFetch = (async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      if (String(input).includes("/models?verbose=true")) {
        return Response.json({
          data: [
            { id: "nvidia/nemotron-3-nano", status: "active" },
            { id: "nvidia/nemotron-3-super", status: "active" },
            { id: "nvidia/nemotron-3-ultra", status: "active" },
          ],
        });
      }
      completionCount += 1;
      if (completionCount === 1) {
        return Response.json({
          choices: [{
            finish_reason: "tool_calls",
            message: {
              role: "assistant",
              content: "",
              tool_calls: [{
                id: "call-malformed",
                type: "function",
                function: { name: "submit", arguments: "{\"answer\":" },
              }],
            },
          }],
        });
      }
      const body = JSON.parse(String(init?.body)) as {
        messages: Array<{ role: string; content: string }>;
        tool_choice: { function: { name: string } };
      };
      expect(body.messages.at(-1)?.content).toContain("valid JSON");
      return Response.json({
        choices: [{
          finish_reason: "tool_calls",
          message: {
            role: "assistant",
            content: "",
            tool_calls: [{
              id: "call-retry",
              type: "function",
              function: { name: body.tool_choice.function.name, arguments: "{\"answer\":\"recovered\"}" },
            }],
          },
        }],
      });
    }) as typeof fetch;
    const client = new TokenFactoryClient({
      apiKey: "test-key",
      projectId: "test-project",
      baseUrl: "http://127.0.0.1:9000/v1",
      fetch: fakeFetch,
    });

    const result = await client.structuredTool({
      role: "narration",
      name: "submit",
      description: "submit",
      parameters: { type: "object" },
      messages: [{ role: "user", content: "narrate" }],
    });

    expect(result).toEqual({ answer: "recovered" });
    expect(completionCount).toBe(2);
  });
});

describe("Token Factory Sandbox workspace", () => {
  it("runs shell-free commands, disables post-clone networking, and chains result images", async () => {
    const commands: Record<string, unknown>[] = [];
    const byOperation = new Map<string, Record<string, unknown>>();
    let operationNumber = 0;
    const fakeFetch = (async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      if (url.endsWith("/instances")) {
        operationNumber += 1;
        const operationId = `00000000-0000-4000-8000-${String(operationNumber).padStart(12, "0")}`;
        const command = JSON.parse(String(init?.body)) as Record<string, unknown>;
        commands.push(command);
        byOperation.set(operationId, command);
        return Response.json({ uuid: operationId }, { status: 201, headers: { location: `/operations/${operationId}` } });
      }
      const operationId = url.slice(url.lastIndexOf("/") + 1);
      const command = byOperation.get(operationId)!;
      const executable = String(command.command);
      const args = command.args as string[];
      const stdout = executable.endsWith("git") && args[0] === "ls-files"
        ? "package.json\0src/index.ts\0"
        : executable.endsWith("cat")
          ? "export const value = 1;\n"
          : executable.endsWith("git") && args[0] === "diff"
            ? "diff --git a/src/index.ts b/src/index.ts\n"
            : "ok\n";
      return Response.json({
        uuid: operationId,
        status: "SUCCESS",
        result_image_uuid: `10000000-0000-4000-8000-${operationId.slice(-12)}`,
        metadata: {
          result: {
            state: { exit_code: 0, timed_out: false },
            stdout: { value: Buffer.from(stdout).toString("base64"), encoding: "base64", truncated: false },
            stderr: { value: "", encoding: "ascii", truncated: false },
          },
        },
      });
    }) as typeof fetch;
    const client = new TokenFactorySandboxClient({
      apiKey: "sandbox-key",
      projectId: "project-id",
      baseUrl: "http://127.0.0.1:9001/sandboxes/v1",
      fetch: fakeFetch,
      sleep: async () => {},
    });
    const operationEvents: string[] = [];
    const workspace = new SandboxWorkspace({
      client,
      baseImage: "tag:node:22",
      repositoryUrl: "https://github.com/example/repository.git",
      revision: "main",
      checks: [{ name: "test", executable: "/usr/bin/npm", args: ["test"] }],
      initialization: [{ executable: "/usr/bin/npm", args: ["ci"], networking: "DISABLED" }],
      operationObserver: {
        started: async (event) => { operationEvents.push(`started:${event.sequence}:${event.operationId}`); },
        completed: async (event, result) => { operationEvents.push(`completed:${event.sequence}:${result.resultImage}`); },
        failed: async (event) => { operationEvents.push(`failed:${event.sequence}`); },
      },
    });

    await workspace.initialize();
    expect(await workspace.listFiles()).toEqual(["package.json", "src/index.ts"]);
    expect(await workspace.readFile("src/index.ts")).toContain("value = 1");
    await workspace.makeDirectory("src/new");
    await workspace.writeFile("src/new/value.ts", "export const value = 2;\n");
    expect((await workspace.runCheck("test")).exitCode).toBe(0);
    expect(await workspace.diff()).toContain("diff --git");

    expect(commands.every((command) => command.shell === false)).toBe(true);
    expect((commands[0]?.networking as { enabled: boolean }).enabled).toBe(true);
    expect(commands.slice(1).every((command) => !(command.networking as { enabled: boolean }).enabled)).toBe(true);
    expect(commands[1]?.image).toBe("10000000-0000-4000-8000-000000000001");
    expect(commands.some((command) => command.command === "/usr/bin/npm" && (command.args as string[])[0] === "ci")).toBe(true);
    const write = commands.find((command) => command.command === "/usr/bin/tee")!;
    expect(Buffer.from((write.stdin as { value: string }).value, "base64").toString("utf8")).toBe("export const value = 2;\n");
    expect(operationEvents).toHaveLength(commands.length * 2);
    expect(operationEvents[0]).toBe("started:1:00000000-0000-4000-8000-000000000001");
    expect(operationEvents[1]).toBe("completed:1:10000000-0000-4000-8000-000000000001");
  });

  it("uploads and mounts a local repository bundle without network access", async () => {
    let uploaded = "";
    let command: Record<string, unknown> | undefined;
    const operationId = "00000000-0000-4000-8000-000000000001";
    const resultImage = "10000000-0000-4000-8000-000000000001";
    const fileUuid = "20000000-0000-4000-8000-000000000001";
    const fakeFetch = (async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      if (url.endsWith("/files")) {
        uploaded = await new Response(init?.body).text();
        return Response.json({ uuid: fileUuid, sha256: "sha256", size: uploaded.length }, { status: 201 });
      }
      if (url.endsWith("/instances")) {
        command = JSON.parse(String(init?.body)) as Record<string, unknown>;
        return Response.json({ uuid: operationId }, { status: 201 });
      }
      return Response.json({
        uuid: operationId,
        status: "SUCCESS",
        result_image_uuid: resultImage,
        metadata: {
          result: {
            state: { exit_code: 0, timed_out: false },
            stdout: { value: "", encoding: "ascii", truncated: false },
            stderr: { value: "", encoding: "ascii", truncated: false },
          },
        },
      });
    }) as typeof fetch;
    const client = new TokenFactorySandboxClient({
      apiKey: "sandbox-key",
      projectId: "project-id",
      baseUrl: "http://127.0.0.1:9001/sandboxes/v1",
      fetch: fakeFetch,
      sleep: async () => {},
    });
    const bundleUuid = await client.uploadFile(Buffer.from("git bundle"));
    const workspace = new SandboxWorkspace({
      client,
      baseImage: "tag:node:22",
      repositoryBundleUuid: bundleUuid,
      revision: "main",
      checks: [],
    });

    await workspace.initialize();

    expect(uploaded).toBe("git bundle");
    expect(command?.args).toEqual(["clone", "--branch", "main", "--", "/workspace/repository.bundle", "/workspace/repository"]);
    expect(command?.networking).toEqual({ enabled: false });
    expect(command?.files).toEqual({
      "/workspace/repository.bundle": { uuid: fileUuid, mode: "0400" },
    });
  });
});

describe("Signalbox governed MCP tools", () => {
  it("returns a public structured denial without executing the denied action", async () => {
    const connection = new FakeGovernanceConnection();
    const tools = new SignalboxMcpTools({
      connection,
      allowedActions: ["requestProductionDeployment", "requestStagingDeployment"],
    });
    const result = await tools.invoke("requestProductionDeployment", { delegation: "denied" }, {
      idempotencyKey: "agent:run:1",
      correlationId: "agent:run",
    });

    expect(result.outcome).toBe("denied");
    if (result.outcome === "denied") {
      expect(result.denial.ruleId).toBe(`authorize:${productionOperation}`);
      expect(result.denial.policyBoundaryId).toBe(productionOperation);
      expect(result.denial.policyId).toBeNull();
      expect(result.denial.decisionEvidence.model).toMatchObject({ version: "0.52.0", sourceHash: "sha256:test" });
    }
    expect(connection.calls.map((call) => call.name)).toEqual(["modellang_public_decision_trace"]);
  });

  it("advertises only operations in the prepared capability closure", async () => {
    const tools = new SignalboxMcpTools({
      connection: new FakeGovernanceConnection(),
      allowedActions: ["requestPullRequest", "requestProductionDeployment", "requestStagingDeployment"],
      executableOperationIds: [pullRequestOperation],
    });
    expect(await tools.definitions()).toEqual([
      expect.objectContaining({ authoredName: "requestPullRequest", operationId: pullRequestOperation }),
    ]);
    expect((await tools.modelTools()).map((tool) => tool.function.name)).toEqual(["signalbox_requestPullRequest"]);
    await expect(tools.invoke("requestProductionDeployment", {}, {
      idempotencyKey: "agent:run:2",
      correlationId: "agent:run",
    })).rejects.toThrow("not allowed");
  });
});

describe("governed coding agent", () => {
  it("edits and tests code, opens a PR, then self-corrects a production denial to staging", async () => {
    const connection = new FakeGovernanceConnection();
    const governance = new SignalboxMcpTools({
      connection,
      allowedActions: ["requestPullRequest", "requestProductionDeployment", "requestStagingDeployment"],
    });
    const sandbox = new FakeWorkspace();
    const inference = new ScriptedInference();
    const agent = new GovernedCodingAgent({
      inference,
      sandbox,
      governance,
      checkNames: ["test"],
      stagingFallback: { input: { delegation: "staging-delegation", environment: "staging", connector: "static", commitSha: "abc" } },
      runId: () => "phase4-run",
      now: () => new Date("2026-08-29T12:00:00.000Z"),
    });

    const result = await agent.run("Fix the defect, test it, then request deployment.");

    expect(result.summary).toBe("Fix implemented and staging requested after production denial.");
    expect(result.diff).toContain("export const fixed = true");
    expect(result.narration.summary).toContain("Production was denied");
    expect(result.timeline).toEqual(expect.arrayContaining([
      expect.objectContaining({ category: "sandbox", operation: "writeFile", outcome: "completed" }),
      expect.objectContaining({ category: "sandbox", operation: "runCheck", outcome: "completed" }),
      expect.objectContaining({ category: "governance", operation: "requestPullRequest", outcome: "executed" }),
      expect.objectContaining({ category: "governance", operation: "requestProductionDeployment", outcome: "denied" }),
      expect.objectContaining({ category: "correction", operation: "handleDenial", outcome: "retryStaging" }),
      expect.objectContaining({ category: "governance", operation: "requestStagingDeployment", outcome: "executed" }),
    ]));
    expect(connection.calls.map((call) => call.name)).toEqual([
      "modellang_public_decision_trace",
      "act-pull-request",
      "modellang_public_decision_trace",
      "modellang_public_decision_trace",
      "act-staging",
    ]);
    const stagingCall = connection.calls.at(-1)!;
    expect(stagingCall._meta).toMatchObject({
      "dev.modellang/idempotencyKey": "agent:phase4-run:6:retryStaging",
      "dev.modellang/correlationId": "agent:phase4-run",
    });
    expect(sandbox.writes).toEqual([{ path: "src/index.ts", content: "export const fixed = true;\n" }]);
    expect(sandbox.checks).toEqual(["test"]);
    expect(inference.roles).toEqual([
      "planner",
      "operator",
      "operator",
      "operator",
      "operator",
      "operator",
      "operator",
      "correction",
      "operator",
      "narration",
    ]);
  });
});

class FakeWorkspace implements SandboxWorkspacePort {
  readonly writes: { path: string; content: string }[] = [];
  readonly checks: string[] = [];
  readonly #result: SandboxResult = {
    operationId: "sandbox-op",
    resultImage: "sandbox-image",
    exitCode: 0,
    timedOut: false,
    stdout: "",
    stderr: "",
    stdoutTruncated: false,
    stderrTruncated: false,
  };

  async initialize(): Promise<SandboxResult> { return this.#result; }
  async listFiles(): Promise<readonly string[]> { return ["src/index.ts"]; }
  async readFile(): Promise<string> { return "export const fixed = false;\n"; }
  async makeDirectory(): Promise<void> {}
  async writeFile(path: string, content: string): Promise<void> { this.writes.push({ path, content }); }
  async runCheck(name: string): Promise<SandboxResult> { this.checks.push(name); return this.#result; }
  async diff(): Promise<string> { return "-export const fixed = false;\n+export const fixed = true;\n"; }
}

class ScriptedInference implements AgentInference {
  readonly roles: string[] = [];
  #operatorTurn = 0;

  async structuredTool(request: StructuredToolRequest): Promise<Record<string, unknown>> {
    this.roles.push(request.role);
    if (request.role === "planner") {
      return {
        summary: "Fix and verify the defect, then request deployment.",
        steps: [{ objective: "Apply the fix", expectedEvidence: "Passing check" }],
        risks: ["Production authority may be denied"],
      };
    }
    if (request.role === "correction") {
      return {
        action: "retryStaging",
        rationale: "The production authorization rule failed while a staging fallback is available.",
        humanMessage: "Production remains blocked; staging was requested instead.",
      };
    }
    return {
      summary: "Production was denied by Signalbox and the agent retried the authorized staging request.",
      controls: ["Runtime authorization was evaluated before each action."],
      unresolved: ["Production still requires independent authority."],
      evidence: ["The production rule failed and the staging action executed."],
    };
  }

  async chat(request: ChatRequest): Promise<ChatReply> {
    this.roles.push(request.role);
    this.#operatorTurn += 1;
    const scripts: ReadonlyArray<{ name: string; arguments: Record<string, unknown> }> = [
      { name: "sandbox_list_files", arguments: { pathPrefix: "" } },
      { name: "sandbox_read_file", arguments: { path: "src/index.ts" } },
      { name: "sandbox_write_file", arguments: { path: "src/index.ts", content: "export const fixed = true;\n" } },
      { name: "sandbox_run_check", arguments: { name: "test" } },
      {
        name: "signalbox_requestPullRequest",
        arguments: {
          delegation: "pull-request-delegation",
          repository: "repository",
          connector: "github",
          headBranch: "agent/fix",
          baseBranch: "main",
          title: "Fix defect",
        },
      },
      {
        name: "signalbox_requestProductionDeployment",
        arguments: { delegation: "production-delegation", environment: "production", connector: "static", commitSha: "abc" },
      },
      { name: "finish_coding_task", arguments: { summary: "Fix implemented and staging requested after production denial." } },
    ];
    const script = scripts[this.#operatorTurn - 1];
    if (!script) throw new Error("Unexpected operator turn");
    return {
      model: "dynamic-super-model",
      finishReason: "tool_calls",
      message: {
        role: "assistant",
        content: null,
        tool_calls: [{
          id: `operator-call-${this.#operatorTurn}`,
          type: "function",
          function: { name: script.name, arguments: JSON.stringify(script.arguments) },
        }],
      },
    };
  }
}
