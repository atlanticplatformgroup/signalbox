import {
  AgentTokenService,
  AgentTokenStoreError,
  type AgentTokenMutationInput,
  type CredentialManagerIdentity,
} from "./agent-tokens.mjs";
import type { BoundIdentity } from "./identity.mjs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const mutationKeys = new Set(["label", "expiresAt"]);
const issueKeys = new Set(["agentId", "label", "expiresAt"]);

function json(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: { "cache-control": "no-store", "content-type": "application/json" },
  });
}

function problem(status: number, code: string, detail: string): Response {
  return Response.json(
    { type: `https://signalbox.dev/problems/${code.toLowerCase()}`, title: detail, status, code },
    { status, headers: { "cache-control": "no-store", "content-type": "application/problem+json" } },
  );
}

async function readObject(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new AgentTokenStoreError("Content-Type must be application/json", 415, "SB_UNSUPPORTED_MEDIA_TYPE");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new AgentTokenStoreError("Request body must be valid JSON", 400, "SB_VALIDATION");
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    total += chunk.value.byteLength;
    if (total > 16_384) {
      await reader.cancel();
      throw new AgentTokenStoreError("Request body is too large", 413, "SB_BODY_TOO_LARGE");
    }
    chunks.push(chunk.value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new AgentTokenStoreError("Request body must be valid JSON", 400, "SB_VALIDATION");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new AgentTokenStoreError("Request body must be an object", 400, "SB_VALIDATION");
  }
  return value as Record<string, unknown>;
}

function mutation(value: Record<string, unknown>, allowed: ReadonlySet<string>): AgentTokenMutationInput {
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new AgentTokenStoreError("Request body contains an unknown field", 400, "SB_VALIDATION");
  }
  if (typeof value.label !== "string" || value.label.length < 1 || value.label.length > 128) {
    throw new AgentTokenStoreError("label must contain 1-128 characters", 400, "SB_VALIDATION");
  }
  if (value.expiresAt !== undefined && value.expiresAt !== null && typeof value.expiresAt !== "string") {
    throw new AgentTokenStoreError("expiresAt must be an ISO 8601 timestamp or null", 400, "SB_VALIDATION");
  }
  let expiresAt: Date | null = null;
  if (typeof value.expiresAt === "string") {
    expiresAt = new Date(value.expiresAt);
    if (!Number.isFinite(expiresAt.getTime()) || expiresAt.toISOString() !== value.expiresAt) {
      throw new AgentTokenStoreError("expiresAt must be a canonical ISO 8601 timestamp", 400, "SB_VALIDATION");
    }
  }
  return { label: value.label, expiresAt };
}

function caller(identity: BoundIdentity): CredentialManagerIdentity {
  return { issuer: identity.issuer, subject: identity.subject };
}

export function createAgentTokenHttpHandler(
  service: AgentTokenService,
  authenticate: (bearerToken: string) => Promise<BoundIdentity | null>,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return problem(405, "SB_METHOD_NOT_ALLOWED", "Agent token operations require POST");
    }
    const authorization = request.headers.get("authorization");
    const bearer = authorization && /^Bearer\s+(.+)$/i.exec(authorization)?.[1];
    if (!bearer) return problem(401, "SB_AUTHENTICATION", "Bearer authentication is required");

    try {
      const identity = await authenticate(bearer);
      if (!identity) return problem(401, "SB_AUTHENTICATION", "Bearer authentication failed");
      const path = new URL(request.url).pathname;

      if (path === "/auth/agent-tokens") {
        const body = await readObject(request);
        if (typeof body.agentId !== "string" || !uuidPattern.test(body.agentId)) {
          throw new AgentTokenStoreError("agentId must be a UUID", 400, "SB_VALIDATION");
        }
        return json(await service.issue(caller(identity), body.agentId, mutation(body, issueKeys)), 201);
      }

      const rotate = /^\/auth\/agent-tokens\/([0-9a-f-]{36})\/rotate$/i.exec(path);
      if (rotate && uuidPattern.test(rotate[1]!)) {
        const body = await readObject(request);
        return json(await service.rotate(caller(identity), rotate[1]!, mutation(body, mutationKeys)), 201);
      }

      const revoke = /^\/auth\/agent-tokens\/([0-9a-f-]{36})\/revoke$/i.exec(path);
      if (revoke && uuidPattern.test(revoke[1]!)) {
        return json(await service.revoke(caller(identity), revoke[1]!));
      }

      return problem(404, "SB_NOT_FOUND", "Agent token operation was not found");
    } catch (error) {
      if (error instanceof AgentTokenStoreError) return problem(error.status, error.code, error.message);
      return problem(500, "SB_INTERNAL", "Internal Server Error");
    }
  };
}
