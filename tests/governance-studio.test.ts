import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { GovernanceBundleCompiler, type CompiledGovernanceBundle } from "../src/architecture/bundle-compiler.mjs";
import { MemoryArtifactStore } from "../src/architecture/object-store.mjs";
import type { GovernanceBundleRecord } from "../src/architecture/repository.mjs";
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

function model(version: string): string {
  return `model GovernedAPI version "${version}";
entity Agent @stableId("ent_20000000000000000000000000000001") {
  id: UUID @id @stableId("fld_20000000000000000000000000000001");
  active: Boolean = true @stableId("fld_20000000000000000000000000000002");
}
entity ApiResource @stableId("ent_20000000000000000000000000000002") {
  id: UUID @id @stableId("fld_20000000000000000000000000000003");
  path: String @unique @stableId("fld_20000000000000000000000000000004");
}
entity ApiRequest @stableId("ent_20000000000000000000000000000003") {
  id: UUID @id @generated(uuid) @stableId("fld_20000000000000000000000000000005");
  resource: ApiResource @stableId("fld_20000000000000000000000000000006");
  requestedBy: Agent @stableId("fld_20000000000000000000000000000007");
}
policy ApiDelegation @stableId("pol_20000000000000000000000000000001")(actor: Agent) {
  allow active_agent @stableId("pbr_20000000000000000000000000000001"): actor.active;
}
action callApi @stableId("act_20000000000000000000000000000001")(caller actor: Agent, resource: ApiResource) -> ApiRequest {
  authorize ApiDelegation(actor);
  idempotency required;
  create ApiRequest { resource = resource; requestedBy = actor; }
}
`;
}

class MemoryStudioRepository implements GovernanceStudioRepository {
  readonly #records = new Map<string, GovernanceBundleRecord>();

  async saveCompiledBundle(orgId: string, createdBy: string, compiled: CompiledGovernanceBundle): Promise<string> {
    const existing = [...this.#records.values()].find((record) => record.orgId === orgId && record.model.sourceHash === compiled.bundle.model.sourceHash);
    if (existing) return existing.id;
    this.#records.set(compiled.id, {
      id: compiled.id,
      orgId,
      status: "COMPILED",
      model: compiled.bundle.model,
      bundleHash: compiled.bundle.bundleHash,
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

  async activateBundle(orgId: string, bundleId: string, activatedBy: string): Promise<{ id: string; previousBundleId: string | null }> {
    const candidate = await this.governanceBundle(orgId, bundleId);
    if (!candidate) throw new Error("Governance bundle does not exist");
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

function studio(): GovernanceStudio {
  const objectStore = new MemoryArtifactStore();
  return new GovernanceStudio({
    objectStore,
    repository: new MemoryStudioRepository(),
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
    expect(firstCandidate).toMatchObject({ ok: true, preview: { agents: ["Agent"], capabilities: ["callApi"] } });
    expect(firstCandidate.preview.resources).toEqual(expect.arrayContaining(["ApiResource", "ApiRequest"]));
    expect(firstCandidate.preview.mcpTools.length).toBeGreaterThan(0);
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
    const crossTenant = await post(instance, "/studio/api/activate", { candidateId: candidate.candidateId }, otherOrg);
    expect(crossTenant.status).toBe(404);
    const agent = { ...human, kind: "AGENT" as const };
    expect((await post(instance, "/studio/api/compile", { source: model("0.2.0") }, agent)).status).toBe(403);
  });

  it("starts fresh without exposing the Signalbox kernel model", async () => {
    const instance = studio();
    const response = await instance.fetch(new Request("http://signalbox.test/studio/api/bootstrap"), human);
    const result = await response.json() as { source: string; boundary: { signalboxOwned: string[]; customerOwned: string[] } };
    expect(result.source).toContain("model CustomerGovernance version \"0.1.0\"");
    expect(result.boundary.signalboxOwned).toEqual(["identity", "credentials", "audit", "approvals", "execution lifecycle"]);
    expect(result.boundary.customerOwned).toEqual(["governed resources", "operations", "constraints", "approval rules"]);
  });
});
