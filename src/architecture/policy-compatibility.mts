import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { sha256Json } from "./contracts.mjs";

/** Studio changes authorization and preconditions, never the deployed data or effect contract. */
export async function verifyPolicyCompatibility(candidate: Record<string, unknown>): Promise<string> {
  const baseline = JSON.parse(await readFile(resolve("generated/signalbox/model.ir.json"), "utf8")) as Record<string, unknown>;
  const expected = sha256Json(structure(baseline));
  if (sha256Json(structure(candidate)) !== expected) {
    throw new TypeError("Studio governs the installed Signalbox actions. Change policies, action authorization, or preconditions only; changes to entities, action inputs/effects, queries, or schema require a reviewed deployment.");
  }
  // Policies used by queries cannot change: this runtime deliberately governs actions only.
  const queryPolicies = new Set<string>();
  for (const action of baseline.actions as Record<string, unknown>[]) {
    if (action.name !== "completeExecution" && action.name !== "failExecution") continue;
    const changed = (candidate.actions as Record<string, unknown>[]).find((item) => item.id === action.id);
    if (!changed || sha256Json(clean(action.authorization)) !== sha256Json(clean(changed.authorization))
      || sha256Json(clean(action.preconditions)) !== sha256Json(clean(changed.preconditions))) {
      throw new TypeError("Completion and failure recording are immutable recovery operations, not customer policy controls.");
    }
  }
  collectPolicyCalls(baseline.queries, queryPolicies);
  for (const action of baseline.actions as Record<string, unknown>[]) {
    if (action.name === "completeExecution" || action.name === "failExecution") collectPolicyCalls(action, queryPolicies);
  }
  for (const id of queryPolicies) {
    const before = (baseline.policies as Record<string, unknown>[]).find((policy) => policy.id === id);
    const after = (candidate.policies as Record<string, unknown>[]).find((policy) => policy.id === id);
    if (sha256Json(clean(before)) !== sha256Json(clean(after))) {
      throw new TypeError("A policy shared with a deployed query cannot be changed through action governance.");
    }
    collectPolicyCalls(before, queryPolicies);
  }
  return expected;
}

function structure(ir: Record<string, unknown>): unknown {
  const { policies: _policies, enforcement: _enforcement, model, actions, ...rest } = ir;
  const { version: _version, sourceHash: _sourceHash, sourceFile: _sourceFile, ...modelIdentity } = model as Record<string, unknown>;
  return clean({
    ...rest,
    model: modelIdentity,
    actions: (actions as Record<string, unknown>[]).map((action) => {
      const { authorization: _authorization, preconditions: _preconditions, lockPlan: _lockPlan, ...contract } = action;
      return contract;
    }),
  });
}

function clean(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(clean);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).filter(([key]) => key !== "span").map(([key, item]) => [key, clean(item)]));
  }
  return value;
}

function collectPolicyCalls(value: unknown, found: Set<string>): void {
  if (Array.isArray(value)) { for (const item of value) collectPolicyCalls(item, found); }
  else if (value && typeof value === "object") {
    const object = value as Record<string, unknown>;
    if (object.kind === "policyCall" && typeof object.policyId === "string") found.add(object.policyId);
    for (const item of Object.values(object)) collectPolicyCalls(item, found);
  }
}
