import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer as createNetServer } from "node:net";
import type { Server } from "node:http";
import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import pg from "pg";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createSignalboxBoundary } from "../src/boundary.mjs";
import { createSignalboxNodeServer } from "../src/server.mjs";
import { SignalboxMcpTools } from "../src/agents/signalbox-mcp.mjs";

const AGENT_PI = "00000000-0000-4000-8000-0000000000b1";
const DELEGATION_ISSUE = "00000000-0000-4000-8000-0000000000f1";
const DELEGATION_STAGING = "00000000-0000-4000-8000-0000000000f3";
const REPOSITORY = "00000000-0000-4000-8000-0000000000d1";
const CONNECTOR_GITHUB = "00000000-0000-4000-8000-0000000000c1";
const CONNECTOR_STATIC = "00000000-0000-4000-8000-0000000000c2";
const ENVIRONMENT_PRODUCTION = "00000000-0000-4000-8000-0000000000e1";
const REQUEST_ISSUE = "act_ea693a4d658449fbab5741b8369bc276";
const MY_ISSUES = "qry_22f082ad9148490eb301e04fdc6e2ce3";
const OIDC_ISSUER = "https://oidc.test";
const OIDC_AUDIENCE = "signalbox";

const seed = readFileSync(new URL("../seed.sql", import.meta.url), "utf8");
const authSql = readFileSync(new URL("../sql/phase2_auth.sql", import.meta.url), "utf8");

function psql(statement: string): string {
  return execFileSync(
    "docker",
    [
      "exec", "-i", "sb-pg16", "psql", "-U", "nebius_admin", "-d", "sb_managed",
      "-tAq", "-v", "ON_ERROR_STOP=1", "-f", "-",
    ],
    { input: statement, encoding: "utf8" },
  ).trim();
}

function sql(statement: string): string {
  return psql(`SET ROLE modellang_owner;\n${statement}`);
}

async function availablePort(): Promise<number> {
  const server = createNetServer();
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Unable to allocate test port");
  await new Promise<void>((resolve) => server.close(() => resolve()));
  return address.port;
}

let pool: pg.Pool;
let origin: string;
let server: Server;
let oidcToken: string;

function githubIdentity(token: string): number | null {
  if (token === "github-dana") return 1002;
  if (token === "github-ops") return 1004;
  if (token === "github-outsider") return 1005;
  if (token === "github-unbound") return 1999;
  return null;
}

async function request(path: string, token: string | null, body: unknown = {}): Promise<Response> {
  return fetch(`${origin}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

async function issueToken(token = "github-ops"): Promise<{
  id: string;
  token: string;
  expiresAt: string | null;
}> {
  const response = await request("/auth/agent-tokens", token, {
    agentId: AGENT_PI,
    label: "integration",
    expiresAt: new Date(Date.now() + 86_400_000).toISOString(),
  });
  expect(response.status, await response.clone().text()).toBe(201);
  return await response.json() as { id: string; token: string; expiresAt: string | null };
}

beforeAll(async () => {
  psql(authSql);
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const jwk = await exportJWK(publicKey);
  jwk.kid = "signalbox-test";
  oidcToken = await new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid: jwk.kid })
    .setIssuer(OIDC_ISSUER)
    .setAudience(OIDC_AUDIENCE)
    .setSubject("user:ops")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);

  const identityFetch: typeof fetch = async (input, init) => {
    const target = new URL(typeof input === "string" || input instanceof URL ? input : input.url);
    if (target.origin === OIDC_ISSUER && target.pathname === "/.well-known/jwks.json") {
      return Response.json({ keys: [jwk] });
    }
    if (target.href === "https://api.github.test/user") {
      const headers = new Headers(init?.headers);
      const id = githubIdentity(headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "");
      return id ? Response.json({ id, login: `user-${id}` }) : new Response(null, { status: 401 });
    }
    return new Response(null, { status: 404 });
  };

  const port = await availablePort();
  origin = `http://127.0.0.1:${port}`;
  pool = new pg.Pool({
    host: "127.0.0.1",
    port: 55433,
    database: "sb_managed",
    user: "sb_gateway_login",
    password: "gw",
    max: 8,
  });
  const boundary = createSignalboxBoundary({
    pool,
    publicOrigin: origin,
    identity: {
      fetch: identityFetch,
      githubApiUrl: "https://api.github.test/",
      oidc: { issuer: OIDC_ISSUER, audience: OIDC_AUDIENCE },
    },
  });
  server = createSignalboxNodeServer(boundary, origin);
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
});

beforeEach(() => {
  sql(seed);
});

afterAll(async () => {
  if (server) await new Promise<void>((resolve) => server.close(() => resolve()));
  if (pool) await pool.end();
});

describe("human authentication", () => {
  it("binds a verified GitHub user to the generated REST executor", async () => {
    const response = await request(`/api/operations/queries/${MY_ISSUES}`, "github-dana");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ items: [], nextCursor: null });
  });

  it("accepts a standards-based OIDC identity only after binding", async () => {
    const response = await request(`/api/operations/queries/${MY_ISSUES}`, oidcToken);
    expect(response.status).toBe(200);
  });

  it("rejects missing, invalid, and valid-but-unbound credentials", async () => {
    for (const token of [null, "invalid", "github-unbound"]) {
      const response = await request(`/api/operations/queries/${MY_ISSUES}`, token);
      expect(response.status, String(token)).toBe(401);
    }
  });

  it("does not accept caller identity in operation input", async () => {
    const response = await request(`/api/operations/queries/${MY_ISSUES}`, "github-dana", {
      actor: AGENT_PI,
    });
    expect(response.status).toBe(400);
  });
});

describe("agent access token lifecycle", () => {
  it("issues only to an authorized human and stores no plaintext token", async () => {
    expect((await request("/auth/agent-tokens", "github-dana", {
      agentId: AGENT_PI,
      label: "unauthorized",
      expiresAt: new Date(Date.now() + 86_400_000).toISOString(),
    })).status).toBe(403);

    const issued = await issueToken();
    expect(issued.token).toMatch(/^sbx_[0-9a-f-]{36}\.[A-Za-z0-9_-]{43}$/i);
    expect(sql(`SELECT token_hash LIKE 'sha256:%' AND token_hash <> '${issued.token}'
      FROM model_signalbox.agent_credential_metadata WHERE id='${issued.id}';`)).toBe("t");
  });

  it("bounds token-management request bodies", async () => {
    const response = await request("/auth/agent-tokens", "github-ops", {
      agentId: AGENT_PI,
      label: "x".repeat(17_000),
      expiresAt: null,
    });
    expect(response.status).toBe(413);
  });

  it("binds an issued agent token to its principal", async () => {
    const issued = await issueToken();
    const response = await request(`/api/operations/actions/${REQUEST_ISSUE}`, issued.token, {
      delegation: DELEGATION_ISSUE,
      repository: REPOSITORY,
      connector: CONNECTOR_GITHUB,
      title: "Authenticated host path",
      body: "Created through the Phase 2 REST boundary.",
    });
    expect(response.status).toBe(400);

    const authorized = await fetch(`${origin}/api/operations/actions/${REQUEST_ISSUE}`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${issued.token}`,
        "content-type": "application/json",
        "idempotency-key": `host-${Date.now()}`,
      },
      body: JSON.stringify({
        delegation: DELEGATION_ISSUE,
        repository: REPOSITORY,
        connector: CONNECTOR_GITHUB,
        title: "Authenticated host path",
        body: "Created through the Phase 2 REST boundary.",
      }),
    });
    expect(authorized.status).toBe(200);
    expect(sql(`SELECT last_used_at IS NOT NULL FROM model_signalbox.agent_credential_metadata WHERE id='${issued.id}';`)).toBe("t");
  });

  it("rotates atomically and invalidates the old token", async () => {
    const original = await issueToken();
    const rotatedResponse = await request(`/auth/agent-tokens/${original.id}/rotate`, "github-ops", {
      label: "rotated",
      expiresAt: new Date(Date.now() + 172_800_000).toISOString(),
    });
    expect(rotatedResponse.status).toBe(201);
    const rotated = await rotatedResponse.json() as { id: string; token: string };
    expect(rotated.id).not.toBe(original.id);
    expect((await request(`/api/operations/queries/${MY_ISSUES}`, original.token)).status).toBe(401);
    expect((await request(`/api/operations/queries/${MY_ISSUES}`, rotated.token)).status).toBe(200);
    expect(sql(`SELECT revoked_at IS NOT NULL FROM model_signalbox.agent_credential_metadata WHERE id='${original.id}';`)).toBe("t");
  });

  it("revokes idempotently and rejects expired or principal-revoked tokens", async () => {
    const revoked = await issueToken();
    const first = await request(`/auth/agent-tokens/${revoked.id}/revoke`, "github-ops");
    const second = await request(`/auth/agent-tokens/${revoked.id}/revoke`, "github-ops");
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect((await first.json()).revokedAt).toBe((await second.json()).revokedAt);
    expect((await request(`/api/operations/queries/${MY_ISSUES}`, revoked.token)).status).toBe(401);

    const expired = await issueToken();
    sql(`UPDATE model_signalbox.agent_credential_metadata SET expires_at=transaction_timestamp() - interval '1 second' WHERE id='${expired.id}';`);
    expect((await request(`/api/operations/queries/${MY_ISSUES}`, expired.token)).status).toBe(401);

    const inactive = await issueToken();
    sql(`UPDATE model_signalbox.principal SET status='REVOKED' WHERE id='${AGENT_PI}';`);
    expect((await request(`/api/operations/queries/${MY_ISSUES}`, inactive.token)).status).toBe(401);
  });
});

describe("MCP protocol boundary", () => {
  it("connects a real MCP client and preserves REST query semantics", async () => {
    const issued = await issueToken();
    const rest = await request(`/api/operations/queries/${MY_ISSUES}`, issued.token);
    expect(rest.status).toBe(200);
    const restResult = await rest.json();

    const client = new Client({ name: "signalbox-integration", version: "1.0.0" });
    const transport = new StreamableHTTPClientTransport(new URL(`${origin}/mcp`), {
      authProvider: { token: async () => issued.token },
    });
    try {
      await client.connect(transport);
      const tools = await client.listTools();
      expect(tools.tools).toHaveLength(25);
      const result = await client.callTool({ name: MY_ISSUES, arguments: {} });
      expect(result.isError).not.toBe(true);
      expect(result.structuredContent).toEqual(restResult);
    } finally {
      await client.close();
    }
  });
  it("discovers the governed coding actions through the production MCP adapter", async () => {
    const issued = await issueToken();
    const tools = await SignalboxMcpTools.connect({
      url: `${origin}/mcp`,
      accessToken: issued.token,
    });
    try {
      expect((await tools.definitions()).map((definition) => definition.authoredName)).toEqual([
        "requestProductionDeployment",
        "requestPullRequest",
        "requestStagingDeployment",
      ]);
      const denied = await tools.invoke("requestProductionDeployment", {
        delegation: DELEGATION_STAGING,
        environment: ENVIRONMENT_PRODUCTION,
        connector: CONNECTOR_STATIC,
        commitSha: "a".repeat(40),
      }, {
        idempotencyKey: "host-test:production-denial",
        correlationId: "host-test:production-denial",
      });
      expect(denied.outcome).toBe("denied");
      if (denied.outcome === "denied") {
        expect(denied.denial.ruleId).toMatch(/^authorize:/);
        expect(denied.denial.policyId).toBeNull();
        expect(denied.denial.policyDisclosure).toBe("withheldByPublicTrace");
        expect(denied.denial.decisionEvidence.model).toMatchObject({
          id: "model:Signalbox",
          version: "0.52.0",
          sourceHash: expect.stringMatching(/^sha256:/),
        });
      }
    } finally {
      await tools.close();
    }
  });


  it("challenges an MCP request without a bearer token", async () => {
    const response = await fetch(`${origin}/mcp`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} }),
    });
    expect(response.status).toBe(401);
    expect(response.headers.get("www-authenticate")).toContain("Bearer");
  });
});
