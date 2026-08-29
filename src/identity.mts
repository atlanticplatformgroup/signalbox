import { createRemoteJWKSet, customFetch, jwtVerify, type JWTPayload, type RemoteJWKSet } from "jose";
import type { Pool } from "pg";
import { AgentTokenService, isAgentAccessToken } from "./agent-tokens.mjs";

const githubIssuer = "https://github.com";

export interface OidcIdentityOptions {
  readonly issuer: string;
  readonly audience: string;
}

export interface IdentityOptions {
  readonly githubApiUrl?: string;
  readonly oidc?: OidcIdentityOptions;
  readonly fetch?: typeof fetch;
  readonly now?: () => Date;
  readonly authenticationLeaseSeconds?: number;
}

export interface BoundIdentity {
  readonly issuer: string;
  readonly subject: string;
  readonly principalId: string;
  readonly orgId: string;
  readonly kind: "HUMAN" | "AGENT";
  readonly expiresAt: number;
}

interface ExternalHumanIdentity {
  readonly issuer: string;
  readonly subject: string;
  readonly expiresAt: number;
}

interface BoundIdentityRow {
  principal_id: string;
  org_id: string;
  principal_kind: "HUMAN" | "AGENT";
}

function bearerPayload(payload: JWTPayload): ExternalHumanIdentity | null {
  if (!payload.iss || !payload.sub || !payload.exp) return null;
  return { issuer: payload.iss, subject: payload.sub, expiresAt: payload.exp };
}

class HumanIdentityVerifier {
  private readonly request: typeof fetch;
  private readonly now: () => Date;
  private readonly githubUserUrl: URL;
  private readonly leaseSeconds: number;
  private readonly oidcKeys?: RemoteJWKSet;

  constructor(private readonly options: IdentityOptions) {
    this.request = options.fetch ?? fetch;
    this.now = options.now ?? (() => new Date());
    this.githubUserUrl = new URL("user", (options.githubApiUrl ?? "https://api.github.com/").replace(/\/?$/, "/"));
    this.leaseSeconds = options.authenticationLeaseSeconds ?? 300;
    if (!Number.isSafeInteger(this.leaseSeconds) || this.leaseSeconds < 1 || this.leaseSeconds > 3600) {
      throw new RangeError("Authentication lease must be between 1 and 3600 seconds");
    }
    if (options.oidc) {
      const issuerUrl = options.oidc.issuer.endsWith("/") ? options.oidc.issuer : `${options.oidc.issuer}/`;
      this.oidcKeys = createRemoteJWKSet(new URL(".well-known/jwks.json", issuerUrl), {
        [customFetch]: this.request,
      });
    }
  }

  async verify(token: string): Promise<ExternalHumanIdentity | null> {
    if (this.options.oidc && this.oidcKeys && token.split(".").length === 3) {
      try {
        const verified = await jwtVerify(token, this.oidcKeys, {
          issuer: this.options.oidc.issuer,
          audience: this.options.oidc.audience,
          algorithms: ["RS256", "ES256"],
          requiredClaims: ["iss", "sub", "aud", "exp"],
        });
        return bearerPayload(verified.payload);
      } catch {
        return null;
      }
    }

    let response: Response;
    try {
      response = await this.request(this.githubUserUrl, {
        headers: {
          accept: "application/vnd.github+json",
          authorization: `Bearer ${token}`,
          "user-agent": "signalbox/0.0.1",
          "x-github-api-version": "2022-11-28",
        },
      });
    } catch {
      return null;
    }
    if (response.status === 401 || response.status === 403) return null;
    if (!response.ok) return null;

    const value = await response.json() as { id?: unknown };
    if ((typeof value.id !== "number" || !Number.isSafeInteger(value.id) || value.id < 1)
      && (typeof value.id !== "string" || !/^[1-9][0-9]*$/.test(value.id))) {
      return null;
    }
    return {
      issuer: githubIssuer,
      subject: `github:user:${String(value.id)}`,
      expiresAt: Math.floor(this.now().getTime() / 1000) + this.leaseSeconds,
    };
  }
}

export class IdentityAuthenticator {
  private readonly humans: HumanIdentityVerifier;

  constructor(
    private readonly pool: Pool,
    private readonly agentTokens: AgentTokenService,
    options: IdentityOptions = {},
  ) {
    this.humans = new HumanIdentityVerifier(options);
  }

  async authenticate(token: string): Promise<BoundIdentity | null> {
    if (isAgentAccessToken(token)) {
      const agent = await this.agentTokens.verify(token);
      return agent && {
        issuer: agent.issuer,
        subject: agent.subject,
        principalId: agent.principalId,
        orgId: agent.orgId,
        kind: "AGENT",
        expiresAt: agent.expiresAt,
      };
    }

    const external = await this.humans.verify(token);
    if (!external) return null;
    const result = await this.pool.query<BoundIdentityRow>(
      "SELECT * FROM model_signalbox_auth.resolve_bound_identity($1, $2)",
      [external.issuer, external.subject],
    );
    const bound = result.rows[0];
    if (!bound || bound.principal_kind !== "HUMAN") return null;
    return {
      issuer: external.issuer,
      subject: external.subject,
      principalId: bound.principal_id,
      orgId: bound.org_id,
      kind: "HUMAN",
      expiresAt: external.expiresAt,
    };
  }
}
