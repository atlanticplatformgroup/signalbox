import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { GovernanceBundleCompiler, type CompiledGovernanceBundle } from "../src/architecture/bundle-compiler.mjs";
import { MemoryArtifactStore, type ObjectArtifactStore } from "../src/architecture/object-store.mjs";
import { GovernanceAdministrationError, verifyGovernanceBundleArtifacts, type GovernanceBundleRecord } from "../src/architecture/repository.mjs";
import { GovernanceStudio, type GovernanceStudioRepository } from "../src/governance-studio.mjs";
import type { BoundIdentity } from "../src/identity.mjs";

const human: BoundIdentity = {
  issuer: "test",
  subject: "governance-author",
  principalId: "00000000-0000-4000-8000-0000000000b4",
  orgId: "00000000-0000-4000-8000-0000000000a1",
  kind: "HUMAN",
  expiresAt: 4_102_444_800,
};
const otherOrg = { ...human, orgId: "00000000-0000-4000-8000-0000000000a2" };
const otherAdmin = { ...otherOrg, principalId: "00000000-0000-4000-8000-0000000000b5" };
const reviewer = { ...human, principalId: "00000000-0000-4000-8000-0000000000b2" };
const baselineSource = readFileSync(new URL("../signalbox.model", import.meta.url), "utf8");

function model(version: string): string {
  return baselineSource.replace(/(model Signalbox version )"[^"]+"/, `$1"${version}"`);
}

class MemoryStudioRepository implements GovernanceStudioRepository {
  readonly #records = new Map<string, GovernanceBundleRecord>();

  readonly admins = new Set([`${human.orgId}:${human.principalId}`, `${otherAdmin.orgId}:${otherAdmin.principalId}`]);

  async canAdministerGovernance(orgId: string, principalId: string): Promise<boolean> {
    return this.admins.has(`${orgId}:${principalId}`);
  }

  async saveCompiledBundle(orgId: string, createdBy: string, compiled: CompiledGovernanceBundle): Promise<string> {
    if (!await this.canAdministerGovernance(orgId, createdBy)) throw new GovernanceAdministrationError();
    const existing = [...this.#records.values()].find((record) => record.orgId === orgId && record.model.sourceHash === compiled.bundle.model.sourceHash);
    if (existing) return existing.id;
    this.#records.set(compiled.id, {
      id: compiled.id,
      orgId,
      status: "COMPILED",
      model: compiled.bundle.model,
      bundleHash: compiled.bundle.bundleHash,
      compilerVersion: compiled.bundle.compilerVersion,
      runtimeCompatibility: compiled.bundle.runtimeCompatibility,
      sourceObjectKey: compiled.sourceObject.key,
      bundleObjectKey: compiled.bundleObject.key,
      previousBundleId: null,
      createdBy,
      createdAt: new Date().toISOString(),
      activatedBy: null,
      activatedAt: null,
    });
    return compiled.id;
  }

  async governanceBundle(orgId: string, bundleId: string): Promise<GovernanceBundleRecord | null> {
    const record = this.#records.get(bundleId);
    return record?.orgId === orgId ? record : null;
  }

  async activeGovernanceBundle(orgId: string): Promise<GovernanceBundleRecord | null> {
    return [...this.#records.values()].find((record) => record.orgId === orgId && record.status === "ACTIVE") ?? null;
  }

  async activateBundle(orgId: string, bundleId: string, activatedBy: string, objectStore: ObjectArtifactStore): Promise<{ id: string; previousBundleId: string | null }> {
    if (!await this.canAdministerGovernance(orgId, activatedBy)) throw new GovernanceAdministrationError();
    const candidate = await this.governanceBundle(orgId, bundleId);
    if (!candidate) throw new Error("Governance bundle does not exist");
    await verifyGovernanceBundleArtifacts(candidate, objectStore);
    const current = await this.activeGovernanceBundle(orgId);
    if (current?.id === bundleId) return { id: bundleId, previousBundleId: null };
    if (current) this.#records.set(current.id, { ...current, status: "RETIRED" });
    const previousBundleId = current?.id ?? null;
    this.#records.set(candidate.id, {
      ...candidate,
      status: "ACTIVE",
      previousBundleId,
      activatedBy,
      activatedAt: new Date().toISOString(),
    });
    return { id: bundleId, previousBundleId };
  }
}

function studio(repository = new MemoryStudioRepository()): GovernanceStudio {
  const objectStore = new MemoryArtifactStore();
  return new GovernanceStudio({
    objectStore,
    repository,
    installer: { install: async () => undefined },
    compiler: new GovernanceBundleCompiler({ objectStore, compiler: resolve("node_modules/.bin/modelc") }),
  });
}

async function post(instance: GovernanceStudio, path: string, body: unknown, identity = human): Promise<Response> {
  return instance.fetch(new Request(`http://signalbox.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  }), identity);
}

describe("GovernanceStudio", () => {
  it("returns line-addressed compiler diagnostics without retaining an invalid candidate", async () => {
    const instance = studio();
    const response = await post(instance, "/studio/api/validate", { source: "model Broken version ;" });
    const result = await response.json() as { ok: boolean; diagnostics: Array<{ line: number; column: number; code: string }> };
    expect(result.ok).toBe(false);
    expect(result.diagnostics[0]).toMatchObject({ line: 1, code: expect.stringMatching(/^(E\d+|SB_MODEL_COMPILE)$/) });
    expect(result.diagnostics[0]!.column).toBeGreaterThan(0);
  });

  it("compiles, previews, atomically activates, and rolls back tenant-scoped immutable bundles", async () => {
    const instance = studio();
    const first = await post(instance, "/studio/api/compile", { source: model("0.2.0") });
    const firstCandidate = await first.json() as { ok: boolean; candidateId: string; preview: { agents: string[]; resources: string[]; capabilities: string[]; mcpTools: string[] } };
    expect(firstCandidate).toMatchObject({
      ok: true,
      preview: {
        capabilities: expect.arrayContaining(["requestIssueCreation", "requestProductionDeployment"]),
        resources: expect.arrayContaining(["Repository", "DeploymentRequest"]),
      },
    });
    const activatedFirst = await post(instance, "/studio/api/activate", { candidateId: firstCandidate.candidateId });
    expect(await activatedFirst.json()).toMatchObject({ ok: true, active: { model: { version: "0.2.0", sourceHash: expect.stringMatching(/^sha256:/) } } });

    const secondCandidate = await (await post(instance, "/studio/api/compile", { source: model("0.3.0") })).json() as { candidateId: string };
    await post(instance, "/studio/api/activate", { candidateId: secondCandidate.candidateId });
    const rolledBack = await post(instance, "/studio/api/rollback", {});
    expect(await rolledBack.json()).toMatchObject({ ok: true, active: { model: { version: "0.2.0" } } });

    const bootstrap = await instance.fetch(new Request("http://signalbox.test/studio/api/bootstrap"), human);
    expect(await bootstrap.json()).toMatchObject({ source: expect.stringContaining('version "0.2.0"') });
    const otherBootstrap = await instance.fetch(new Request("http://signalbox.test/studio/api/bootstrap"), otherOrg);
    expect(await otherBootstrap.json()).toMatchObject({ active: null });
  });

  it("rejects agent identities and cross-tenant candidate activation", async () => {
    const instance = studio();
    const candidate = await (await post(instance, "/studio/api/compile", { source: model("0.2.0") })).json() as { candidateId: string };
    const crossTenant = await post(instance, "/studio/api/activate", { candidateId: candidate.candidateId }, otherAdmin);
    expect(crossTenant.status).toBe(404);
    const agent = { ...human, kind: "AGENT" as const };
    expect((await post(instance, "/studio/api/compile", { source: model("0.2.0") }, agent)).status).toBe(403);
  });

  it("lets reviewers read and validate without granting compile, activation, or rollback authority", async () => {
    const instance = studio();
    const bootstrap = await instance.fetch(new Request("http://signalbox.test/studio/api/bootstrap"), reviewer);
    expect(await bootstrap.json()).toMatchObject({ permissions: { canAdministerGovernance: false } });
    expect(await (await post(instance, "/studio/api/validate", { source: model("0.2.0") }, reviewer)).json()).toMatchObject({ ok: true });
    for (const path of ["compile", "activate", "rollback"]) {
      const denied = await post(instance, `/studio/api/${path}`, { source: model("0.2.0") }, reviewer);
      expect(denied.status).toBe(403);
      expect(await denied.json()).toMatchObject({ code: "SB_GOVERNANCE_ADMIN_REQUIRED" });
    }
  });

  it("rechecks governance administration after authoring and rejects a mismatched bound organization", async () => {
    const repository = new MemoryStudioRepository();
    const instance = studio(repository);
    const candidate = await (await post(instance, "/studio/api/compile", { source: model("0.2.0") })).json() as { candidateId: string };
    repository.admins.delete(`${human.orgId}:${human.principalId}`);
    const revoked = await post(instance, "/studio/api/activate", { candidateId: candidate.candidateId });
    expect(revoked.status).toBe(403);
    const wrongOrg = await post(instance, "/studio/api/compile", { source: model("0.2.0") }, otherOrg);
    expect(wrongOrg.status).toBe(403);
    expect(await repository.activeGovernanceBundle(human.orgId)).toBeNull();
  });

  it("bootstraps an editable fixed Signalbox policy without publishing it", async () => {
    const instance = studio();
    const response = await instance.fetch(new Request("http://signalbox.test/studio/api/bootstrap"), human);
    const result = await response.json() as { source: string; baselineSource: string; active: unknown };
    expect(result.active).toBeNull();
    const validation = await post(instance, "/studio/api/validate", { source: result.source });
    expect(await validation.json()).toMatchObject({ ok: true, model: { name: "Signalbox" } });
    expect((await (await instance.fetch(new Request("http://signalbox.test/studio/api/bootstrap"), human)).json()).active).toBeNull();
  });
});
