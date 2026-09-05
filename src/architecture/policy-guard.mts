import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { PoolClient } from "pg";

interface OperationManifest {
  readonly model: { readonly sourceHash: string };
  readonly entities: readonly { readonly id: string; readonly name: string }[];
  readonly operations: readonly {
    readonly id: string;
    readonly name: string;
    readonly kind: string;
    readonly input: readonly { readonly id: string; readonly name: string }[];
  }[];
}
interface DecisionPlan {
  readonly model: { readonly sourceHash: string };
  readonly actions: readonly {
    readonly operationId: string;
    readonly callableParameterIds: readonly string[];
    readonly entityLoads: readonly {
      readonly parameterId: string;
      readonly entityId: string;
      readonly source: string;
      readonly executionLock: string;
      readonly order: number;
    }[];
  }[];
}

// These are compiler names, never policy source or request-supplied SQL. PostgreSQL
// resolves and validates every resulting identifier/signature before wrapping it.
function sqlName(name: string): string {
  const result = name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").replace(/([A-Z])([A-Z][a-z])/g, "$1_$2").toLowerCase();
  if (!/^[a-z][a-z0-9_]{0,53}$/.test(result)) throw new Error(`Unsupported generated SQL name: ${name}`);
  return result;
}

export function policyGuardMetadata(operations: OperationManifest, decisions: DecisionPlan): unknown[] {
  if (operations.model.sourceHash !== decisions.model.sourceHash) throw new Error("Baseline metadata source hashes differ");
  const actions = operations.operations.filter((operation) => operation.kind === "action");
  if (actions.length === 0 || actions.length !== decisions.actions.length) throw new Error("Incomplete baseline decision metadata");
  const entities = new Map(operations.entities.map((entity) => [entity.id, sqlName(entity.name)]));
  return actions.map((operation) => {
    const decision = decisions.actions.find((candidate) => candidate.operationId === operation.id);
    if (!decision || !/^action:act_[a-z0-9]+$/.test(operation.id)
      || JSON.stringify(decision.callableParameterIds) !== JSON.stringify(operation.input.map((parameter) => parameter.id))) {
      throw new Error(`Incompatible decision metadata for ${operation.id}`);
    }
    return {
      operationId: operation.id,
      baselineSourceHash: decisions.model.sourceHash,
      actionName: sqlName(operation.name),
      decisionName: `decide_${operation.id.slice("action:".length)}`,
      parameters: operation.input.map((parameter) => `p_${sqlName(parameter.name)}`),
      locks: [...decision.entityLoads].sort((left, right) => left.order - right.order).map((load) => {
        const table = entities.get(load.entityId);
        const index = operation.input.findIndex((parameter) => parameter.id === load.parameterId);
        if (!table || !["share", "update"].includes(load.executionLock)
          || !["authenticatedContext", "operationInput"].includes(load.source)
          || (load.source === "operationInput" && index < 0)) throw new Error(`Unsupported entity lock for ${operation.id}`);
        return { table, parameter: load.source === "authenticatedContext" ? null : `p_${sqlName(operation.input[index]!.name)}`, mode: load.executionLock };
      }),
    };
  });
}

/** Apply once, after generated SQL and phases 2/3/5, on a privileged dedicated connection. */
export async function installPolicyGuards(
  client: Pick<PoolClient, "query">,
  generatedDirectory = "generated/signalbox",
  migrationPath = "sql/phase6_policy_enforcement.sql",
): Promise<void> {
  const [operations, decisions, migration] = await Promise.all([
    readFile(join(generatedDirectory, "operations.json"), "utf8"),
    readFile(join(generatedDirectory, "decisions.json"), "utf8"),
    readFile(migrationPath, "utf8"),
  ]);
  const metadata = policyGuardMetadata(JSON.parse(operations) as OperationManifest, JSON.parse(decisions) as DecisionPlan);
  await client.query("SELECT pg_catalog.set_config('signalbox.policy_guard_metadata', $1, false)", [JSON.stringify(metadata)]);
  try {
    await client.query(migration);
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    await client.query("RESET signalbox.policy_guard_metadata");
  }
}
