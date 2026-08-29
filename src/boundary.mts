import type { Pool } from "pg";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";
import { createSignalboxHttpHandler } from "../generated/signalbox/dist/http-server.js";
import { createSignalboxMcpHandler } from "../generated/signalbox/dist/mcp-server.js";
import { createAgentTokenHttpHandler } from "./agent-token-http.mjs";
import { AgentTokenService } from "./agent-tokens.mjs";
import { IdentityAuthenticator, type BoundIdentity, type IdentityOptions } from "./identity.mjs";

export interface SignalboxBoundaryOptions {
  readonly pool: Pool;
  readonly publicOrigin: string;
  readonly agentTokenIssuer?: string;
  readonly identity?: IdentityOptions;
}

export interface SignalboxBoundary {
  readonly agentTokens: AgentTokenService;
  readonly identities: IdentityAuthenticator;
  authenticate(bearerToken: string): Promise<BoundIdentity | null>;
  fetch(request: Request): Promise<Response>;
}

export function createSignalboxBoundary(options: SignalboxBoundaryOptions): SignalboxBoundary {
  const origin = new URL(options.publicOrigin);
  if (!/^https?:$/.test(origin.protocol) || origin.username || origin.password || origin.search || origin.hash) {
    throw new Error("publicOrigin must be an HTTP(S) URL without credentials, query, or fragment");
  }
  const mcpUrl = new URL("/mcp", origin);
  const tokenIssuer = options.agentTokenIssuer ?? new URL("/auth/agent-tokens", origin).href;
  const agentTokens = new AgentTokenService(options.pool, tokenIssuer, options.identity?.now);
  const identities = new IdentityAuthenticator(options.pool, agentTokens, options.identity);

  const authenticate = (bearerToken: string) => identities.authenticate(bearerToken);
  const authenticatedExecutor = async (bearerToken: string) => {
    const identity = await authenticate(bearerToken);
    if (!identity) return null;
    return {
      identity,
      executor: createSignalboxGatewayExecutor(options.pool, identity),
    };
  };

  const rest = createSignalboxHttpHandler(
    async (bearerToken) => (await authenticatedExecutor(bearerToken))?.executor ?? null,
    { basePath: "/api" },
  );
  const mcp = createSignalboxMcpHandler(
    async (bearerToken) => {
      const authenticated = await authenticatedExecutor(bearerToken);
      if (!authenticated) return null;
      return {
        authInfo: {
          token: bearerToken,
          clientId: `signalbox:${authenticated.identity.principalId}`,
          scopes: ["signalbox"],
          expiresAt: authenticated.identity.expiresAt,
          resource: mcpUrl,
        },
        executor: authenticated.executor,
      };
    },
    { resourceServerUrl: mcpUrl.href, discoveryCacheTtlMs: 0 },
  );
  const tokenHttp = createAgentTokenHttpHandler(agentTokens, authenticate);

  return {
    agentTokens,
    identities,
    authenticate,
    async fetch(request: Request): Promise<Response> {
      const path = new URL(request.url).pathname;
      if (path === mcpUrl.pathname) return mcp.fetch(request);
      if (path === "/auth/agent-tokens" || path.startsWith("/auth/agent-tokens/")) {
        return tokenHttp(request);
      }
      if (path === "/api" || path.startsWith("/api/")) return rest(request);
      return Response.json(
        { type: "https://signalbox.dev/problems/not-found", title: "Not Found", status: 404, code: "SB_NOT_FOUND" },
        { status: 404, headers: { "content-type": "application/problem+json" } },
      );
    },
  };
}
