import { createHash, randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import {
  governanceBundleFormat,
  withBundleHash,
  type BindingKind,
  type GovernanceBundle,
  type GovernanceOperation,
  type GovernanceBundlePreview,
} from "./contracts.mjs";
import type { ObjectArtifactStore, StoredObject } from "./object-store.mjs";

const maximumSourceBytes = 512 * 1024;
const compilerTimeoutMs = 30_000;

export interface GovernanceBundleCompilerOptions {
  readonly objectStore: ObjectArtifactStore;
  readonly compiler?: string;
  readonly runtimeCompatibility?: string;
}

export interface CompiledGovernanceBundle {
  readonly id: string;
  readonly bundle: GovernanceBundle;
  readonly sourceObject: StoredObject;
  readonly bundleObject: StoredObject;
}

export class GovernanceBundleCompileError extends Error {
  constructor(readonly diagnostic: string) {
    super("Governance bundle compilation failed");
  }
}

interface ToolCatalog {
  readonly model?: { readonly name?: unknown; readonly version?: unknown; readonly sourceHash?: unknown };
  readonly compilerVersion?: unknown;
  readonly tools?: unknown;
}

interface ToolContract {
  readonly id?: unknown;
  readonly name?: unknown;
  readonly description?: unknown;
  readonly inputSchema?: unknown;
}

interface ModelIr {
  readonly entities?: Array<{ readonly name?: unknown }>;
  readonly actions?: Array<{ readonly name?: unknown }>;
  readonly policies?: Array<{ readonly name?: unknown }>;
}

export class GovernanceBundleCompiler {
  readonly #objectStore: ObjectArtifactStore;
  readonly #compiler: string;
  readonly #runtimeCompatibility: string;

  constructor(options: GovernanceBundleCompilerOptions) {
    this.#objectStore = options.objectStore;
    this.#compiler = resolve(options.compiler ?? "node_modules/.bin/modelc");
    this.#runtimeCompatibility = options.runtimeCompatibility ?? "signalbox-governance-runtime/1";
  }

  async compile(orgId: string, source: string): Promise<CompiledGovernanceBundle> {
    const normalized = source.replace(/\r\n?/g, "\n");
    if (!normalized.trim()) throw new TypeError("Governance source is required");
    if (Buffer.byteLength(normalized) > maximumSourceBytes) throw new RangeError("Governance source exceeds 512 KiB");
    const directory = await mkdtemp(join(tmpdir(), "signalbox-bundle-"));
    try {
      const modelPath = join(directory, "customer.model");
      const output = join(directory, "generated");
      await writeFile(modelPath, normalized, { encoding: "utf8", mode: 0o600 });
      const compile = await runCompiler(this.#compiler, ["build", modelPath, "--out", output]);
      if (compile.code !== 0) throw new GovernanceBundleCompileError(compile.stderr || "The compiler returned no diagnostic");

      const tools = parseJson<ToolCatalog>(await readFile(join(output, "agent-tools.json"), "utf8"), "agent tool catalog");
      const decisions = parseJson<Record<string, unknown>>(await readFile(join(output, "decisions.json"), "utf8"), "decision graph");
      const provenance = parseJson<Record<string, unknown>>(await readFile(join(output, "provenance.json"), "utf8"), "provenance");
      const ir = parseJson<ModelIr>(await readFile(join(output, "model.ir.json"), "utf8"), "model IR");
      const model = parseModel(tools);
      const expectedSourceHash = `sha256:${createHash("sha256").update(normalized).digest("hex")}`;
      if (model.sourceHash !== expectedSourceHash) throw new Error("Compiler source hash does not match the submitted governance source");
      const operations = parseOperations(tools.tools);
      const bundle = withBundleHash({
        format: governanceBundleFormat,
        model,
        compilerVersion: requiredString(tools.compilerVersion, "compilerVersion"),
        runtimeCompatibility: this.#runtimeCompatibility,
        operations,
        preview: parsePreview(ir, operations),
        decisionGraph: decisions,
        provenance,
      });
      const sourceBytes = Buffer.from(normalized, "utf8");
      const bundleBytes = Buffer.from(JSON.stringify(bundle), "utf8");
      const [sourceObject, bundleObject] = await Promise.all([
        this.#objectStore.put(orgId, "MODEL_SOURCE", sourceBytes, "text/plain; charset=utf-8"),
        this.#objectStore.put(orgId, "GOVERNANCE_BUNDLE", bundleBytes, "application/vnd.signalbox.governance-bundle+json"),
      ]);
      return { id: randomUUID(), bundle, sourceObject, bundleObject };
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }
}

function parseModel(catalog: ToolCatalog): GovernanceBundle["model"] {
  if (!catalog.model || typeof catalog.model !== "object") throw new Error("Agent tool catalog omitted model identity");
  return {
    name: requiredString(catalog.model.name, "model.name"),
    version: requiredString(catalog.model.version, "model.version"),
    sourceHash: requiredHash(catalog.model.sourceHash, "model.sourceHash"),
  };
}

function parseOperations(value: unknown): readonly GovernanceOperation[] {
  if (!Array.isArray(value)) throw new Error("Agent tool catalog tools must be an array");
  const operations = value.map((candidate, index) => {
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) throw new Error(`Tool ${index} must be an object`);
    const tool = candidate as ToolContract;
    const inputSchema = recordValue(tool.inputSchema, `tools[${index}].inputSchema`);
    return {
      operationId: requiredString(tool.id, `tools[${index}].id`),
      name: requiredString(tool.name, `tools[${index}].name`),
      description: requiredString(tool.description, `tools[${index}].description`),
      inputSchema,
      requiredBindings: inferredBindings(inputSchema),
    };
  });
  if (new Set(operations.map((operation) => operation.operationId)).size !== operations.length) throw new Error("Governance bundle operation IDs must be unique");
  return operations;
}

function parsePreview(ir: ModelIr, operations: readonly GovernanceOperation[]): GovernanceBundlePreview {
  const names = (values: ModelIr["entities"], field: string): string[] =>
    (values ?? []).map((value, index) => requiredString(value.name, `${field}[${index}].name`));
  const resources = names(ir.entities, "entities");
  const actions = names(ir.actions, "actions");
  const policies = names(ir.policies, "policies");
  return {
    agents: resources.filter((name) => /agent|principal/i.test(name)),
    connectors: resources.filter((name) => /connector|integration/i.test(name)),
    resources: resources.filter((name) => !/agent|principal|connector|integration/i.test(name)),
    capabilities: actions,
    delegations: policies.filter((name) => /delegat|grant|scope/i.test(name)),
    approvalBoundaries: [...policies.filter((name) => /approv|review/i.test(name)), ...actions.filter((name) => /approv|reject/i.test(name))],
    mcpTools: operations.map((operation) => operation.name),
  };
}

function inferredBindings(schema: Readonly<Record<string, unknown>>): readonly BindingKind[] {
  const properties = recordValue(schema.properties ?? {}, "tool input schema properties");
  const names = new Set(Object.keys(properties));
  const bindings = new Set<BindingKind>(["DELEGATION", "QUOTA"]);
  if (["resource", "repository", "environment", "database"].some((name) => names.has(name))) bindings.add("RESOURCE");
  if (names.has("connector")) {
    bindings.add("CONNECTOR");
    bindings.add("CREDENTIAL");
  }
  return [...bindings].sort();
}

async function runCompiler(executable: string, args: readonly string[]): Promise<{ code: number; stderr: string }> {
  return await new Promise((resolvePromise) => {
    const child = spawn(executable, args, { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => { if (stderr.length < 64 * 1024) stderr += chunk; });
    const timeout = setTimeout(() => child.kill("SIGKILL"), compilerTimeoutMs);
    let settled = false;
    const settle = (value: { code: number; stderr: string }) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolvePromise(value);
    };
    child.once("error", (error) => settle({ code: 1, stderr: error.message }));
    child.once("close", (code, signal) => settle({ code: code ?? 1, stderr: signal === "SIGKILL" ? "Compilation exceeded 30 seconds" : stderr }));
  });
}

function parseJson<T>(text: string, name: string): T {
  try { return JSON.parse(text) as T; }
  catch { throw new Error(`Compiler ${name} is not valid JSON`); }
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || !value) throw new Error(`${name} must be a non-empty string`);
  return value;
}

function requiredHash(value: unknown, name: string): string {
  const text = requiredString(value, name);
  if (!/^sha256:[0-9a-f]{64}$/.test(text)) throw new Error(`${name} must be a SHA-256 digest`);
  return text;
}

function recordValue(value: unknown, name: string): Readonly<Record<string, unknown>> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} must be an object`);
  return value as Readonly<Record<string, unknown>>;
}
