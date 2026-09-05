import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import type { BoundIdentity } from "./identity.mjs";
import { GovernanceBundleCompileError, GovernanceBundleCompiler } from "./architecture/bundle-compiler.mjs";
import type { GovernanceBundle, GovernanceBundlePreview } from "./architecture/contracts.mjs";
import type { ObjectArtifactStore } from "./architecture/object-store.mjs";
import { GovernanceAdministrationError, type ArchitectureRepository, type GovernanceBundleRecord } from "./architecture/repository.mjs";
import type { PolicyInstaller } from "./architecture/policy-installer.mjs";

const MAX_SOURCE_BYTES = 512 * 1024;

export interface GovernanceStudioRepository {
  canAdministerGovernance: ArchitectureRepository["canAdministerGovernance"];
  saveCompiledBundle: ArchitectureRepository["saveCompiledBundle"];
  governanceBundle: ArchitectureRepository["governanceBundle"];
  activeGovernanceBundle: ArchitectureRepository["activeGovernanceBundle"];
  activateBundle: ArchitectureRepository["activateBundle"];
}

export interface GovernanceStudioOptions {
  readonly repository: GovernanceStudioRepository;
  readonly compiler: GovernanceBundleCompiler;
  readonly objectStore: ObjectArtifactStore;
  readonly installer: PolicyInstaller;
  readonly activity?: (identity: BoundIdentity) => Promise<unknown[]>;
}
interface VersionRecord {
  readonly id: string;
  readonly createdAt: string;
  readonly activatedAt: string;
  readonly activatedBy: string;
  readonly model: GovernanceBundle["model"];
  readonly artifacts: readonly string[];
  readonly previousVersionId: string | null;
}

interface CompileResult {
  readonly ok: boolean;
  readonly diagnostics: readonly Diagnostic[];
  readonly preview?: GovernanceBundlePreview;
  readonly artifacts?: readonly string[];
  readonly model?: GovernanceBundle["model"];
  readonly candidateId?: string;
}

interface Diagnostic {
  readonly severity: "error";
  readonly code: string;
  readonly message: string;
  readonly line: number;
  readonly column: number;
}

class CandidateNotFoundError extends Error {}

function compilerDiagnostic(output: string): Diagnostic[] {
  const first = output.trim();
  if (!first) return [{ severity: "error", code: "SB_MODEL_COMPILE", message: "The compiler did not return a diagnostic.", line: 1, column: 1 }];
  const match = /^(E\d+)\s+[^:\n]+:(\d+):(\d+)\n?([\s\S]*)$/.exec(first);
  if (!match) return [{ severity: "error", code: "SB_MODEL_COMPILE", message: first, line: 1, column: 1 }];
  return [{ severity: "error", code: match[1]!, line: Number(match[2]), column: Number(match[3]), message: match[4]!.trim() }];
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status, headers: { "cache-control": "no-store" } });
}

async function bodySource(request: Request): Promise<string> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_SOURCE_BYTES) throw new RangeError("Model source exceeds 512 KiB.");
  const body = await request.json() as { source?: unknown };
  if (typeof body.source !== "string" || !body.source.trim()) throw new TypeError("source must be a non-empty string");
  if (Buffer.byteLength(body.source) > MAX_SOURCE_BYTES) throw new RangeError("Model source exceeds 512 KiB.");
  return body.source.replace(/\r\n?/g, "\n");
}

export class GovernanceStudio {
  readonly #repository: GovernanceStudioRepository;
  readonly #compiler: GovernanceBundleCompiler;
  readonly #objectStore: ObjectArtifactStore;
  readonly #installer: PolicyInstaller;
  readonly #activity?: (identity: BoundIdentity) => Promise<unknown[]>;

  constructor(options: GovernanceStudioOptions) {
    this.#repository = options.repository;
    this.#compiler = options.compiler;
    this.#objectStore = options.objectStore;
    this.#installer = options.installer;
    this.#activity = options.activity;
  }

  async #compile(source: string, retain: boolean, identity: BoundIdentity): Promise<CompileResult> {
    try {
      const compiled = retain ? await this.#compiler.compile(identity.orgId, source) : null;
      const bundle = compiled?.bundle ?? (await this.#compiler.validate(identity.orgId, source)).bundle;
      const candidateId = compiled
        ? await this.#repository.saveCompiledBundle(identity.orgId, identity.principalId, compiled)
        : undefined;
      return {
        ok: true,
        diagnostics: [],
        preview: bundle.preview,
        artifacts: ["customer.model", "governance-bundle.json"],
        model: bundle.model,
        ...(candidateId ? { candidateId } : {}),
      };
    } catch (error) {
      if (error instanceof GovernanceBundleCompileError) {
        return { ok: false, diagnostics: compilerDiagnostic(error.diagnostic) };
      }
      throw error;
    }
  }


  async #version(record: GovernanceBundleRecord): Promise<VersionRecord> {
    if (!record.activatedAt || !record.activatedBy) throw new Error("Active governance bundle omitted activation evidence");
    return {
      id: record.id,
      createdAt: record.createdAt,
      activatedAt: record.activatedAt,
      activatedBy: record.activatedBy,
      model: record.model,
      artifacts: ["customer.model", "governance-bundle.json"],
      previousVersionId: record.previousBundleId,
    };
  }

  async fetch(request: Request, identity: BoundIdentity): Promise<Response> {
    if (identity.kind !== "HUMAN") return json({ code: "SB_HUMAN_REQUIRED", message: "Governance authoring requires a human identity." }, 403);
    const url = new URL(request.url);
    try {
      const mutation = request.method === "POST"
        && ["/studio/api/compile", "/studio/api/activate", "/studio/api/rollback"].includes(url.pathname);
      if (mutation && !await this.#repository.canAdministerGovernance(identity.orgId, identity.principalId)) {
        throw new GovernanceAdministrationError();
      }
      if (request.method === "GET" && url.pathname === "/studio/api/bootstrap") {
        const activeRecord = await this.#repository.activeGovernanceBundle(identity.orgId);
        const baselineSource = await readFile("signalbox.model", "utf8");
        let source = baselineSource;
        if (activeRecord) {
          source = new TextDecoder().decode(await this.#objectStore.get(activeRecord.sourceObjectKey));
          const hash = `sha256:${createHash("sha256").update(source).digest("hex")}`;
          if (hash !== activeRecord.model.sourceHash) throw new Error("Stored governance source does not match immutable database metadata");
        }
        return json({
          source,
          baselineSource,
          active: activeRecord ? await this.#version(activeRecord) : null,
          permissions: { canAdministerGovernance: await this.#repository.canAdministerGovernance(identity.orgId, identity.principalId) },
          boundary: {
            signalboxOwned: ["identity", "credentials", "tenant isolation", "data schema", "actions and effects", "audit", "execution lifecycle"],
            customerOwned: ["additional action policies", "action preconditions", "approval restrictions"],
          },
        });
      }
      if (request.method === "GET" && url.pathname === "/studio/api/activity") {
        if (!this.#activity) return json({ code: "SB_ACTIVITY_UNAVAILABLE", message: "Action evidence storage is not configured." }, 503);
        const catalog = JSON.parse(await readFile("generated/signalbox/operations.json", "utf8")) as { operations: { id: string; name: string }[] };
        return json({ items: await this.#activity(identity), operationNames: Object.fromEntries(catalog.operations.map((operation) => [operation.id, operation.name])) });
      }
      if (request.method === "POST" && url.pathname === "/studio/api/validate") {
        return json(await this.#compile(await bodySource(request), false, identity));
      }
      if (request.method === "POST" && url.pathname === "/studio/api/compile") {
        return json(await this.#compile(await bodySource(request), true, identity));
      }
      if (request.method === "POST" && url.pathname === "/studio/api/activate") {
        const body = await request.json() as { candidateId?: unknown };
        if (typeof body.candidateId !== "string" || !/^[0-9a-f-]{36}$/.test(body.candidateId)) throw new TypeError("candidateId is required");
        const candidate = await this.#repository.governanceBundle(identity.orgId, body.candidateId);
        if (!candidate) throw new CandidateNotFoundError();
        await this.#installer.install(identity.orgId, candidate.id, identity.principalId);
        await this.#repository.activateBundle(identity.orgId, candidate.id, identity.principalId, this.#objectStore);
        const active = await this.#repository.activeGovernanceBundle(identity.orgId);
        if (!active) throw new Error("Activated governance bundle was not persisted");
        return json({ ok: true, active: await this.#version(active) });
      }
      if (request.method === "POST" && url.pathname === "/studio/api/rollback") {
        const current = await this.#repository.activeGovernanceBundle(identity.orgId);
        if (!current?.previousBundleId) return json({ code: "SB_NO_ROLLBACK", message: "No prior active model is available." }, 409);
        const previous = await this.#repository.governanceBundle(identity.orgId, current.previousBundleId);
        if (!previous) throw new Error("Previous immutable governance bundle is unavailable");
        await this.#installer.install(identity.orgId, previous.id, identity.principalId);
        await this.#repository.activateBundle(identity.orgId, previous.id, identity.principalId, this.#objectStore);
        const active = await this.#repository.activeGovernanceBundle(identity.orgId);
        if (!active) throw new Error("Rolled-back governance bundle was not persisted");
        return json({ ok: true, active: await this.#version(active) });
      }
      return json({ code: "SB_NOT_FOUND", message: "Not found." }, 404);
    } catch (error) {
      if (error instanceof GovernanceAdministrationError) return json({ code: error.code, message: error.message }, 403);
      if (error instanceof SyntaxError || error instanceof TypeError || error instanceof RangeError) return json({ code: "SB_INVALID_REQUEST", message: error.message }, 400);
      if (error instanceof CandidateNotFoundError) return json({ code: "SB_CANDIDATE_NOT_FOUND", message: "The compiled candidate does not exist." }, 404);
      throw error;
    }
  }
}
