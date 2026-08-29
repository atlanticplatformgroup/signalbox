import { createHash, randomBytes } from "node:crypto";
import type { Pool } from "pg";

const tokenPattern = /^sbx_([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.([A-Za-z0-9_-]{43})$/i;

export interface CredentialManagerIdentity {
  readonly issuer: string;
  readonly subject: string;
}

export interface AgentTokenMutationInput {
  readonly label: string;
  readonly expiresAt: Date | null;
}

export interface IssuedAgentToken {
  readonly id: string;
  readonly orgId: string;
  readonly agentId: string;
  readonly label: string;
  readonly expiresAt: string | null;
  readonly token: string;
}

export interface RevokedAgentToken {
  readonly id: string;
  readonly agentId: string;
  readonly revokedAt: string;
}

export interface VerifiedAgentIdentity {
  readonly issuer: string;
  readonly subject: string;
  readonly principalId: string;
  readonly orgId: string;
  readonly expiresAt: number;
}

export class AgentTokenStoreError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "AgentTokenStoreError";
  }
}

interface CredentialRow {
  credential_id: string;
  credential_org_id: string;
  credential_agent_id: string;
  credential_label: string;
  credential_expires_at: Date | string | null;
}

interface RevokedCredentialRow {
  credential_id: string;
  credential_agent_id: string;
  credential_revoked_at: Date | string;
}

interface VerifiedCredentialRow {
  identity_issuer: string;
  identity_subject: string;
  principal_id: string;
  org_id: string;
  credential_expires_at: Date | string | null;
}

function secret(): string {
  return randomBytes(32).toString("base64url");
}

function hashSecret(value: string): string {
  return `sha256:${createHash("sha256").update(value, "utf8").digest("hex")}`;
}

function iso(value: Date | string | null): string | null {
  if (value === null) return null;
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function storeError(error: unknown): AgentTokenStoreError {
  const database = error as { code?: string; message?: string };
  const message = database.message ?? "Agent token storage failed";
  if (database.code === "42501") {
    return new AgentTokenStoreError("Agent token management is not authorized", 403, "SB_AUTHORIZATION", { cause: error });
  }
  if (database.code === "22023") {
    return new AgentTokenStoreError("Agent token input is invalid", 400, "SB_VALIDATION", { cause: error });
  }
  if (database.code === "P0002") {
    return new AgentTokenStoreError("Agent token or principal was not found", 404, "SB_NOT_FOUND", { cause: error });
  }
  if (database.code === "P0001" || database.code === "23505") {
    return new AgentTokenStoreError("Agent token state conflicts with this operation", 409, "SB_CONFLICT", { cause: error });
  }
  return new AgentTokenStoreError(message, 500, "SB_STORAGE", { cause: error });
}

function issued(row: CredentialRow, value: string): IssuedAgentToken {
  return {
    id: row.credential_id,
    orgId: row.credential_org_id,
    agentId: row.credential_agent_id,
    label: row.credential_label,
    expiresAt: iso(row.credential_expires_at),
    token: `sbx_${row.credential_id}.${value}`,
  };
}

export class AgentTokenService {
  constructor(
    private readonly pool: Pool,
    readonly issuer: string,
    private readonly now: () => Date = () => new Date(),
  ) {
    if (issuer.length < 1 || issuer.length > 512) throw new RangeError("Agent token issuer must contain 1-512 characters");
  }

  async issue(
    caller: CredentialManagerIdentity,
    agentId: string,
    input: AgentTokenMutationInput,
  ): Promise<IssuedAgentToken> {
    const value = secret();
    try {
      const result = await this.pool.query<CredentialRow>(
        "SELECT * FROM model_signalbox_auth.issue_agent_token($1, $2, $3, $4, $5, $6, $7)",
        [caller.issuer, caller.subject, agentId, input.label, hashSecret(value), input.expiresAt, this.issuer],
      );
      const row = result.rows[0];
      if (!row) throw new Error("Agent token issue function returned no row");
      return issued(row, value);
    } catch (error) {
      throw storeError(error);
    }
  }

  async rotate(
    caller: CredentialManagerIdentity,
    credentialId: string,
    input: AgentTokenMutationInput,
  ): Promise<IssuedAgentToken> {
    const value = secret();
    try {
      const result = await this.pool.query<CredentialRow>(
        "SELECT * FROM model_signalbox_auth.rotate_agent_token($1, $2, $3, $4, $5, $6, $7)",
        [caller.issuer, caller.subject, credentialId, input.label, hashSecret(value), input.expiresAt, this.issuer],
      );
      const row = result.rows[0];
      if (!row) throw new Error("Agent token rotation function returned no row");
      return issued(row, value);
    } catch (error) {
      throw storeError(error);
    }
  }

  async revoke(caller: CredentialManagerIdentity, credentialId: string): Promise<RevokedAgentToken> {
    try {
      const result = await this.pool.query<RevokedCredentialRow>(
        "SELECT * FROM model_signalbox_auth.revoke_agent_token($1, $2, $3)",
        [caller.issuer, caller.subject, credentialId],
      );
      const row = result.rows[0];
      if (!row) throw new Error("Agent token revoke function returned no row");
      return {
        id: row.credential_id,
        agentId: row.credential_agent_id,
        revokedAt: iso(row.credential_revoked_at)!,
      };
    } catch (error) {
      throw storeError(error);
    }
  }

  async verify(token: string): Promise<VerifiedAgentIdentity | null> {
    const parsed = tokenPattern.exec(token);
    if (!parsed) return null;
    try {
      const result = await this.pool.query<VerifiedCredentialRow>(
        "SELECT * FROM model_signalbox_auth.verify_agent_token($1, $2, $3)",
        [parsed[1], hashSecret(parsed[2]!), this.issuer],
      );
      const row = result.rows[0];
      if (!row) return null;
      const storedExpiration = row.credential_expires_at === null
        ? null
        : new Date(row.credential_expires_at).getTime();
      const expiresAt = storedExpiration === null
        ? Math.floor(this.now().getTime() / 1000) + 300
        : Math.floor(storedExpiration / 1000);
      return {
        issuer: row.identity_issuer,
        subject: row.identity_subject,
        principalId: row.principal_id,
        orgId: row.org_id,
        expiresAt,
      };
    } catch {
      return null;
    }
  }
}

export function isAgentAccessToken(token: string): boolean {
  return token.startsWith("sbx_");
}
