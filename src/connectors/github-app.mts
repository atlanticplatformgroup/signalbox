import { importPKCS8, SignJWT } from "jose";
import {
  ConnectorFailure,
  type ExecutionClaim,
  type ExecutionConnector,
  requireString,
  throwIfAborted,
} from "./connector.mjs";

export interface GitHubAppConnectorOptions {
  readonly appId: string;
  readonly installationId: string;
  readonly privateKeyPem: string;
  readonly apiBaseUrl?: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
}

export class GitHubAppConnector implements ExecutionConnector {
  readonly kind = "GITHUB" as const;
  private readonly apiBaseUrl: URL;
  private readonly request: typeof globalThis.fetch;
  private readonly now: () => number;
  private installationToken?: { value: string; expiresAt: number };

  constructor(private readonly options: GitHubAppConnectorOptions) {
    if (!/^\d+$/.test(options.appId) || !/^\d+$/.test(options.installationId)) {
      throw new Error("GitHub App and installation IDs must be decimal strings");
    }
    this.apiBaseUrl = new URL(options.apiBaseUrl ?? "https://api.github.com/");
    if (this.apiBaseUrl.protocol !== "https:" && this.apiBaseUrl.hostname !== "127.0.0.1" && this.apiBaseUrl.hostname !== "localhost") {
      throw new Error("GitHub API base URL must use HTTPS");
    }
    this.request = options.fetch ?? globalThis.fetch;
    this.now = options.now ?? Date.now;
  }

  async recover(claim: ExecutionClaim, signal: AbortSignal): Promise<string | undefined> {
    if (claim.requestKind !== "ISSUE" && claim.requestKind !== "PULL_REQUEST") {
      throw new ConnectorFailure("CONNECTOR_KIND_MISMATCH", false);
    }
    throwIfAborted(signal);
    const token = await this.accessToken(signal);
    const owner = requireString(claim.payload, "owner");
    const repository = requireString(claim.payload, "repository");
    const marker = `<!-- signalbox-execution:${claim.executionId} -->`;
    const path = claim.requestKind === "ISSUE"
      ? `repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/issues`
      : `repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/pulls`;
    return this.findExisting(path, marker, claim.requestKind, token, claim, signal);
  }

  async execute(claim: ExecutionClaim, signal: AbortSignal): Promise<string> {
    if (claim.requestKind !== "ISSUE" && claim.requestKind !== "PULL_REQUEST") {
      throw new ConnectorFailure("CONNECTOR_KIND_MISMATCH", false);
    }
    throwIfAborted(signal);
    const token = await this.accessToken(signal);
    const owner = requireString(claim.payload, "owner");
    const repository = requireString(claim.payload, "repository");
    const marker = `<!-- signalbox-execution:${claim.executionId} -->`;
    const path = claim.requestKind === "ISSUE"
      ? `repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/issues`
      : `repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}/pulls`;

    const existing = await this.findExisting(path, marker, claim.requestKind, token, claim, signal);
    if (existing) return existing;

    const body = claim.requestKind === "ISSUE"
      ? {
          title: requireString(claim.payload, "title"),
          body: `${requireString(claim.payload, "body")}\n\n${marker}`,
        }
      : {
          title: requireString(claim.payload, "title"),
          head: requireString(claim.payload, "headBranch"),
          base: requireString(claim.payload, "baseBranch"),
          body: marker,
        };
    const response = await this.github(path, token, claim, signal, { method: "POST", body: JSON.stringify(body) });
    const created = await readJson(response);
    if (!created || typeof created !== "object" || !("html_url" in created)
      || typeof created.html_url !== "string" || created.html_url.length === 0) {
      throw new ConnectorFailure("GITHUB_INVALID_RESPONSE", true);
    }
    return created.html_url;
  }

  private async findExisting(
    path: string,
    marker: string,
    requestKind: "ISSUE" | "PULL_REQUEST",
    token: string,
    claim: ExecutionClaim,
    signal: AbortSignal,
  ): Promise<string | undefined> {
    const separator = path.includes("?") ? "&" : "?";
    const response = await this.github(`${path}${separator}state=all&per_page=100`, token, claim, signal);
    const rows = await readJson(response);
    if (!Array.isArray(rows)) throw new ConnectorFailure("GITHUB_INVALID_RESPONSE", true);
    for (const row of rows) {
      if (row && typeof row === "object"
        && typeof row.body === "string"
        && row.body.includes(marker)
        && (requestKind !== "ISSUE" || row.pull_request === undefined)
        && typeof row.html_url === "string") {
        return row.html_url;
      }
    }
    return undefined;
  }

  private async accessToken(signal: AbortSignal): Promise<string> {
    if (this.installationToken && this.installationToken.expiresAt - this.now() > 60_000) {
      return this.installationToken.value;
    }
    const nowSeconds = Math.floor(this.now() / 1000);
    let key: Awaited<ReturnType<typeof importPKCS8>>;
    try {
      key = await importPKCS8(this.options.privateKeyPem, "RS256");
    } catch (error) {
      throw new ConnectorFailure("GITHUB_APP_KEY_INVALID", false, { cause: error });
    }
    const jwt = await new SignJWT({})
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(this.options.appId)
      .setIssuedAt(nowSeconds - 30)
      .setExpirationTime(nowSeconds + 540)
      .sign(key);
    const response = await this.raw(`app/installations/${this.options.installationId}/access_tokens`, signal, {
      method: "POST",
      headers: { authorization: `Bearer ${jwt}` },
    });
    const result = await readJson(response);
    if (!result || typeof result !== "object"
      || !("token" in result)
      || !("expires_at" in result)
      || typeof result.token !== "string"
      || typeof result.expires_at !== "string") {
      throw new ConnectorFailure("GITHUB_INVALID_RESPONSE", true);
    }
    const expiresAt = Date.parse(result.expires_at);
    if (!Number.isFinite(expiresAt)) throw new ConnectorFailure("GITHUB_INVALID_RESPONSE", true);
    this.installationToken = { value: result.token, expiresAt };
    return result.token;
  }

  private github(
    path: string,
    token: string,
    claim: ExecutionClaim,
    signal: AbortSignal,
    init: RequestInit = {},
  ): Promise<Response> {
    return this.raw(path, signal, {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": claim.executionId,
        "x-signalbox-correlation-id": claim.correlationId,
        ...(claim.causationId ? { "x-signalbox-causation-id": claim.causationId } : {}),
        ...init.headers,
      },
    });
  }

  private async raw(path: string, signal: AbortSignal, init: RequestInit): Promise<Response> {
    throwIfAborted(signal);
    let response: Response;
    try {
      response = await this.request(new URL(path, this.apiBaseUrl), {
        ...init,
        signal,
        headers: {
          accept: "application/vnd.github+json",
          "content-type": "application/json",
          "user-agent": "signalbox-worker",
          "x-github-api-version": "2022-11-28",
          ...init.headers,
        },
      });
    } catch (error) {
      if (signal.aborted) throw new ConnectorFailure("CONNECTOR_TIMEOUT", true, { cause: error });
      throw new ConnectorFailure("GITHUB_NETWORK", true, { cause: error });
    }
    if (!response.ok) {
      const retryable = response.status === 408 || response.status === 429 || response.status >= 500;
      throw new ConnectorFailure(`GITHUB_HTTP_${response.status}`, retryable);
    }
    return response;
  }
}

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch (error) {
    throw new ConnectorFailure("GITHUB_INVALID_RESPONSE", true, { cause: error });
  }
}

