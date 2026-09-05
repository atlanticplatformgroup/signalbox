import { readFileSync } from "node:fs";
import type { SignalboxOperationExecutor } from "../../generated/signalbox/dist/http-server.js";
import type { ApplicabilityDecision } from "../../generated/signalbox/dist/types.js";

const baseline = JSON.parse(readFileSync(new URL("../../generated/signalbox/decisions.json", import.meta.url), "utf8")) as {
  actions: { operationId: string; preconditions: { id: string }[] }[];
};
const publicRequirements = new Map(baseline.actions.map((action) => [action.operationId, new Set(action.preconditions.map((rule) => rule.id))]));

/** Keep database policy provenance in the tenant audit, outside ModelLang's closed public contract. */
export function publicDecisionExecutor(executor: SignalboxOperationExecutor): SignalboxOperationExecutor {
  return {
    execute: (operationId, input, options) => executor.execute(operationId, input, options),
    async assess(operationId, input, options): Promise<ApplicabilityDecision> {
      const decision = await executor.assess(operationId, input, options);
      if (decision.operationId !== operationId) throw new Error("Assessment operation does not match the request");
      // Tenant requirements and missing-policy guards are private policy details.
      // Expose their refusal at the public boundary, never as permission.
      if (decision.status === "denied" || (decision.status === "notApplicable"
        && !publicRequirements.get(operationId)?.has(decision.explanation?.ruleId ?? ""))) {
        return { operationId, status: "denied", applicable: false, authority: "none",
          explanation: { kind: "authorization", ruleId: `authorize:${operationId}` } };
      }
      return {
        operationId: decision.operationId, status: decision.status,
        applicable: decision.applicable, authority: decision.authority,
        ...(decision.revision === undefined ? {} : { revision: decision.revision }),
        ...(decision.explanation === undefined ? {} : { explanation: decision.explanation }),
      };
    },
  };
}
