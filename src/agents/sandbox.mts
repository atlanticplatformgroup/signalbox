import { Buffer } from "node:buffer";
import { posix } from "node:path";
import { objectValue, optionalString, stringValue } from "./validation.mjs";

export interface SandboxCommand {
  readonly image: string;
  readonly executable: string;
  readonly args?: readonly string[];
  readonly cwd?: string;
  readonly env?: Readonly<Record<string, string>>;
  readonly stdin?: string;
  readonly networking?: boolean;
  readonly timeoutSeconds?: number;
  readonly disposable?: boolean;
}

export interface SandboxResult {
  readonly operationId: string;
  readonly resultImage?: string;
  readonly exitCode: number;
  readonly timedOut: boolean;
  readonly stdout: string;
  readonly stderr: string;
  readonly stdoutTruncated: boolean;
  readonly stderrTruncated: boolean;
}

export interface SandboxClientOptions {
  readonly apiKey: string;
  readonly projectId: string;
  readonly baseUrl?: string;
  readonly fetch?: typeof fetch;
  readonly pollIntervalMs?: number;
  readonly operationTimeoutMs?: number;
  readonly requestTimeoutMs?: number;
  readonly truncateOutputAt?: number;
  readonly sleep?: (milliseconds: number) => Promise<void>;
  readonly now?: () => number;
}

export class TokenFactorySandboxClient {
  readonly #apiKey: string;
  readonly #projectId: string;
  readonly #baseUrl: string;
  readonly #fetch: typeof fetch;
  readonly #pollIntervalMs: number;
  readonly #operationTimeoutMs: number;
  readonly #requestTimeoutMs: number;
  readonly #truncateOutputAt: number;
  readonly #sleep: (milliseconds: number) => Promise<void>;
  readonly #now: () => number;

  constructor(options: SandboxClientOptions) {
    if (!options.apiKey) throw new Error("Sandbox API key is required");
    if (!options.projectId) throw new Error("Sandbox project ID is required");
    this.#apiKey = options.apiKey;
    this.#projectId = options.projectId;
    this.#baseUrl = normalizeBaseUrl(options.baseUrl ?? "https://api.tokenfactory.nebius.com/sandboxes/v1");
    this.#fetch = options.fetch ?? fetch;
    this.#pollIntervalMs = boundedInteger(options.pollIntervalMs ?? 1_000, 1, 30_000, "pollIntervalMs");
    this.#operationTimeoutMs = boundedInteger(options.operationTimeoutMs ?? 300_000, 1_000, 3_600_000, "operationTimeoutMs");
    this.#requestTimeoutMs = boundedInteger(options.requestTimeoutMs ?? 30_000, 1_000, 300_000, "requestTimeoutMs");
    this.#truncateOutputAt = boundedInteger(options.truncateOutputAt ?? 262_144, 1, 10_485_760, "truncateOutputAt");
    this.#sleep = options.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
    this.#now = options.now ?? Date.now;
  }

  async run(command: SandboxCommand): Promise<SandboxResult> {
    validateImage(command.image);
    validateExecutable(command.executable);
    const timeoutSeconds = boundedInteger(command.timeoutSeconds ?? 120, 1, 3_600, "timeoutSeconds");
    const body = {
      image: command.image,
      command: command.executable,
      args: command.args ?? [],
      shell: false,
      disposable: command.disposable ?? false,
      cwd: command.cwd ?? "",
      env: command.env ?? { PATH: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" },
      preserve_env: false,
      networking: { enabled: command.networking ?? false },
      timeout: timeoutSeconds,
      truncate_output_at: this.#truncateOutputAt,
      ...(command.stdin === undefined ? {} : {
        stdin: {
          value: Buffer.from(command.stdin, "utf8").toString("base64"),
          encoding: "base64",
          close: true,
        },
      }),
    };
    const started = await this.#request("instances", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }, [201, 202]);
    const startedBody = objectValue(await started.json(), "Sandbox instance response");
    const operationId = optionalString(startedBody.uuid, "Sandbox instance response.uuid")
      ?? operationIdFromLocation(started.headers.get("location"));
    if (!operationId) throw new Error("Sandbox instance response omitted operation UUID");
    return await this.#wait(operationId);
  }

  async #wait(operationId: string): Promise<SandboxResult> {
    const deadline = this.#now() + this.#operationTimeoutMs;
    while (this.#now() <= deadline) {
      const response = await this.#request(`operations/${encodeURIComponent(operationId)}`, { method: "GET" }, [200]);
      const operation = objectValue(await response.json(), "Sandbox operation");
      const status = stringValue(operation.status, "Sandbox operation.status");
      if (status === "SUCCESS") return parseSandboxResult(operation, operationId);
      if (status === "FAILED" || status === "CANCELLED") {
        throw new Error(`Sandbox operation ${operationId} ${status.toLowerCase()}: ${optionalString(operation.error, "Sandbox operation.error") ?? "no detail"}`);
      }
      if (status !== "PENDING" && status !== "ASSIGNED" && status !== "EXECUTING") {
        throw new Error(`Sandbox operation ${operationId} returned unknown status '${status}'`);
      }
      const retryAfter = response.headers.get("retry-after");
      const waitMs = retryAfter && /^\d+$/.test(retryAfter)
        ? Math.min(Number(retryAfter) * 1_000, 30_000)
        : this.#pollIntervalMs;
      await this.#sleep(waitMs);
    }
    throw new Error(`Sandbox operation ${operationId} exceeded ${this.#operationTimeoutMs}ms`);
  }

  async #request(path: string, init: RequestInit, expectedStatuses: readonly number[]): Promise<Response> {
    const headers = new Headers(init.headers);
    headers.set("authorization", `Bearer ${this.#apiKey}`);
    headers.set("project", this.#projectId);
    headers.set("accept", "application/json");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#requestTimeoutMs);
    let response: Response;
    try {
      response = await this.#fetch(`${this.#baseUrl}/${path}`, { ...init, headers, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
    if (!expectedStatuses.includes(response.status)) {
      const detail = (await response.text()).slice(0, 2_000);
      throw new Error(`Sandbox request failed (${response.status}): ${detail || response.statusText}`);
    }
    return response;
  }
}

export interface SandboxCheck {
  readonly name: string;
  readonly executable: string;
  readonly args: readonly string[];
  readonly timeoutSeconds?: number;
}

export interface SandboxWorkspaceOptions {
  readonly client: TokenFactorySandboxClient;
  readonly baseImage: string;
  readonly repositoryUrl: string;
  readonly revision: string;
  readonly checks: readonly SandboxCheck[];
  readonly workspaceRoot?: string;
  readonly gitExecutable?: string;
  readonly catExecutable?: string;
  readonly teeExecutable?: string;
  readonly mkdirExecutable?: string;
  readonly maxCommands?: number;
  readonly maxWriteBytes?: number;
}

export interface SandboxWorkspacePort {
  initialize(): Promise<SandboxResult>;
  listFiles(pathPrefix?: string): Promise<readonly string[]>;
  readFile(path: string): Promise<string>;
  makeDirectory(path: string): Promise<void>;
  writeFile(path: string, content: string): Promise<void>;
  runCheck(name: string): Promise<SandboxResult>;
  diff(): Promise<string>;
}

export class SandboxWorkspace implements SandboxWorkspacePort {
  readonly #client: TokenFactorySandboxClient;
  readonly #baseImage: string;
  readonly #repositoryUrl: string;
  readonly #revision: string;
  readonly #checks: ReadonlyMap<string, SandboxCheck>;
  readonly #workspaceRoot: string;
  readonly #repositoryRoot: string;
  readonly #gitExecutable: string;
  readonly #catExecutable: string;
  readonly #teeExecutable: string;
  readonly #mkdirExecutable: string;
  readonly #maxCommands: number;
  readonly #maxWriteBytes: number;
  #image?: string;
  #commandCount = 0;

  constructor(options: SandboxWorkspaceOptions) {
    validateRepositoryUrl(options.repositoryUrl);
    if (!/^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/.test(options.revision)) {
      throw new Error("Sandbox repository revision is invalid");
    }
    this.#client = options.client;
    this.#baseImage = options.baseImage;
    this.#repositoryUrl = options.repositoryUrl;
    this.#revision = options.revision;
    this.#checks = new Map(options.checks.map((check) => [check.name, validateCheck(check)]));
    if (this.#checks.size !== options.checks.length) throw new Error("Sandbox check names must be unique");
    this.#workspaceRoot = absolutePath(options.workspaceRoot ?? "/workspace", "workspaceRoot");
    this.#repositoryRoot = posix.join(this.#workspaceRoot, "repository");
    this.#gitExecutable = executablePath(options.gitExecutable ?? "/usr/bin/git", "gitExecutable");
    this.#catExecutable = executablePath(options.catExecutable ?? "/bin/cat", "catExecutable");
    this.#teeExecutable = executablePath(options.teeExecutable ?? "/usr/bin/tee", "teeExecutable");
    this.#mkdirExecutable = executablePath(options.mkdirExecutable ?? "/bin/mkdir", "mkdirExecutable");
    this.#maxCommands = boundedInteger(options.maxCommands ?? 64, 1, 256, "maxCommands");
    this.#maxWriteBytes = boundedInteger(options.maxWriteBytes ?? 1_048_576, 1, 10_485_760, "maxWriteBytes");
  }

  async initialize(): Promise<SandboxResult> {
    if (this.#image) throw new Error("Sandbox workspace is already initialized");
    const result = await this.#execute({
      image: this.#baseImage,
      executable: this.#gitExecutable,
      args: ["clone", "--depth", "1", "--branch", this.#revision, "--", this.#repositoryUrl, this.#repositoryRoot],
      cwd: this.#workspaceRoot,
      networking: true,
      timeoutSeconds: 180,
      disposable: false,
    });
    if (result.exitCode !== 0) throw new Error(`Sandbox repository clone failed: ${result.stderr || result.stdout}`);
    return result;
  }
  async listFiles(pathPrefix?: string): Promise<readonly string[]> {
    const args = ["ls-files", "-z", "--", ...(pathPrefix === undefined ? [] : [this.#relativePath(pathPrefix)])];
    const result = await this.#runInRepository(this.#gitExecutable, args, undefined, 30);
    if (result.exitCode !== 0) throw new Error(`Sandbox file listing failed: ${result.stderr || result.stdout}`);
    if (result.stdoutTruncated) throw new Error("Sandbox file listing exceeded the output limit");
    return result.stdout.split("\0").filter(Boolean);
  }


  async readFile(path: string): Promise<string> {
    const result = await this.#runInRepository(this.#catExecutable, [this.#filePath(path)], undefined, 30);
    if (result.exitCode !== 0) throw new Error(`Sandbox read failed for '${path}': ${result.stderr || result.stdout}`);
    if (result.stdoutTruncated) throw new Error(`Sandbox read for '${path}' exceeded the output limit`);
    return result.stdout;
  }
  async makeDirectory(path: string): Promise<void> {
    const result = await this.#runInRepository(this.#mkdirExecutable, ["-p", "--", this.#filePath(path)], undefined, 30);
    if (result.exitCode !== 0) throw new Error(`Sandbox directory creation failed for '${path}': ${result.stderr || result.stdout}`);
  }


  async writeFile(path: string, content: string): Promise<void> {
    if (Buffer.byteLength(content, "utf8") > this.#maxWriteBytes) {
      throw new Error(`Sandbox write for '${path}' exceeds ${this.#maxWriteBytes} bytes`);
    }
    const result = await this.#runInRepository(this.#teeExecutable, [this.#filePath(path)], content, 30);
    if (result.exitCode !== 0) throw new Error(`Sandbox write failed for '${path}': ${result.stderr || result.stdout}`);
  }

  async runCheck(name: string): Promise<SandboxResult> {
    const check = this.#checks.get(name);
    if (!check) throw new Error(`Unknown sandbox check '${name}'`);
    return await this.#runInRepository(check.executable, check.args, undefined, check.timeoutSeconds ?? 180);
  }

  async diff(): Promise<string> {
    const result = await this.#runInRepository(this.#gitExecutable, ["diff", "--no-ext-diff", "--binary", "--"], undefined, 30);
    if (result.exitCode !== 0) throw new Error(`Sandbox git diff failed: ${result.stderr || result.stdout}`);
    if (result.stdoutTruncated) throw new Error("Sandbox git diff exceeded the output limit");
    return result.stdout;
  }

  async #runInRepository(executable: string, args: readonly string[], stdin: string | undefined, timeoutSeconds: number): Promise<SandboxResult> {
    if (!this.#image) throw new Error("Sandbox workspace is not initialized");
    return await this.#execute({
      image: this.#image,
      executable,
      args,
      cwd: this.#repositoryRoot,
      stdin,
      networking: false,
      timeoutSeconds,
      disposable: false,
    });
  }

  async #execute(command: SandboxCommand): Promise<SandboxResult> {
    this.#commandCount += 1;
    if (this.#commandCount > this.#maxCommands) throw new Error(`Sandbox workspace exceeded ${this.#maxCommands} commands`);
    const result = await this.#client.run(command);
    if (!result.resultImage) throw new Error(`Sandbox operation ${result.operationId} did not return a persistent result image`);
    this.#image = result.resultImage;
    return result;
  }

  #relativePath(value: string): string {
    if (!value || value.includes("\0") || posix.isAbsolute(value)) throw new Error("Sandbox file path must be relative");
    const normalized = posix.normalize(value);
    if (normalized === ".." || normalized.startsWith("../")) throw new Error("Sandbox file path escapes the repository");
    return normalized;
  }

  #filePath(value: string): string {
    return posix.join(this.#repositoryRoot, this.#relativePath(value));
  }
}

function parseSandboxResult(operation: Record<string, unknown>, operationId: string): SandboxResult {
  const metadata = objectValue(operation.metadata, "Sandbox operation.metadata");
  const result = objectValue(metadata.result, "Sandbox operation.metadata.result");
  const state = objectValue(result.state, "Sandbox operation.metadata.result.state");
  const exitCode = state.exit_code;
  if (typeof exitCode !== "number" || !Number.isSafeInteger(exitCode)) {
    throw new Error("Sandbox operation result omitted an integer exit code");
  }
  const timedOut = state.timed_out;
  if (typeof timedOut !== "boolean") throw new Error("Sandbox operation result omitted timed_out");
  const stdout = parseStream(result.stdout, "stdout");
  const stderr = parseStream(result.stderr, "stderr");
  return {
    operationId,
    resultImage: optionalString(operation.result_image_uuid, "Sandbox operation.result_image_uuid"),
    exitCode,
    timedOut,
    stdout: stdout.value,
    stderr: stderr.value,
    stdoutTruncated: stdout.truncated,
    stderrTruncated: stderr.truncated,
  };
}

function parseStream(value: unknown, name: string): { value: string; truncated: boolean } {
  if (value === undefined || value === null) return { value: "", truncated: false };
  const stream = objectValue(value, `Sandbox operation ${name}`);
  const encoded = typeof stream.value === "string"
    ? stream.value
    : (() => { throw new Error(`Sandbox operation ${name}.value must be a string`); })();
  const encoding = stringValue(stream.encoding, `Sandbox operation ${name}.encoding`);
  if (encoding !== "ascii" && encoding !== "base64") throw new Error(`Sandbox operation ${name}.encoding is invalid`);
  const truncated = stream.truncated === undefined ? false : stream.truncated;
  if (typeof truncated !== "boolean") throw new Error(`Sandbox operation ${name}.truncated must be boolean`);
  return { value: encoding === "base64" ? Buffer.from(encoded, "base64").toString("utf8") : encoded, truncated };
}

function validateRepositoryUrl(value: string): void {
  const url = new URL(value);
  if (url.protocol !== "https:") throw new Error("Sandbox repository URL must use HTTPS");
  if (url.username || url.password) throw new Error("Sandbox repository URL must not contain credentials");
}

function validateImage(value: string): void {
  if (!value || (!value.startsWith("tag:") && !/^[0-9a-f-]{36}$/i.test(value))) {
    throw new Error("Sandbox image must be a UUID or tag: reference");
  }
}

function validateExecutable(value: string): void {
  executablePath(value, "Sandbox executable");
}

function executablePath(value: string, name: string): string {
  if (!posix.isAbsolute(value) || value.includes("\0") || posix.normalize(value) !== value) {
    throw new Error(`${name} must be a normalized absolute path`);
  }
  return value;
}

function absolutePath(value: string, name: string): string {
  if (!posix.isAbsolute(value) || value.includes("\0")) throw new Error(`${name} must be absolute`);
  return posix.normalize(value);
}

function validateCheck(check: SandboxCheck): SandboxCheck {
  if (!/^[a-z][a-z0-9_-]{0,31}$/.test(check.name)) throw new Error("Sandbox check name is invalid");
  validateExecutable(check.executable);
  if (check.args.some((argument) => argument.includes("\0"))) throw new Error(`Sandbox check '${check.name}' has an invalid argument`);
  if (check.timeoutSeconds !== undefined) boundedInteger(check.timeoutSeconds, 1, 3_600, `check ${check.name} timeoutSeconds`);
  return check;
}

function operationIdFromLocation(location: string | null): string | undefined {
  if (!location) return undefined;
  const segments = location.split("/").filter(Boolean);
  return segments.at(-1);
}

function normalizeBaseUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:" && url.hostname !== "127.0.0.1" && url.hostname !== "localhost") {
    throw new Error("Sandbox baseUrl must use HTTPS except for localhost tests");
  }
  return url.toString().replace(/\/$/, "");
}

function boundedInteger(value: number, minimum: number, maximum: number, name: string): number {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}
