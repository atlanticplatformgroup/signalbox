import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

type OperationManifest = {
  operations: Array<{
    id: string;
    name: string;
    kind: "action" | "query";
    caller: {
      source: string;
      requestSupplied: boolean;
    };
  }>;
};

type IrOperation = {
  id: string;
  name: string;
  callerParameterId: string;
  tenantOpen?: true;
};

type IrManifest = {
  tenant?: {
    entityId: string;
    principalFieldId: string;
    scopedEntities: Array<{ entityId: string; fieldId: string }>;
  };
  entities: Array<{ id: string; name: string }>;
  actions: IrOperation[];
  queries: IrOperation[];
};

type EnforcementManifest = {
  enforcement: Array<{ id: string }>;
};

const generated = new URL("../generated/signalbox/", import.meta.url);
const readJson = <T>(name: string): T =>
  JSON.parse(readFileSync(new URL(name, generated), "utf8")) as T;

const operations = readJson<OperationManifest>("operations.json");
const ir = readJson<IrManifest>("model.ir.json");
const enforcement = readJson<EnforcementManifest>("enforcement.json");

const expectedOperations = [
  "approveProductionDeployment",
  "approveSchemaMigration",
  "completeExecution",
  "deploymentApprovalInbox",
  "dispatchApprovedDeployment",
  "dispatchApprovedSchemaMigration",
  "dispatchIssueCreation",
  "dispatchPullRequest",
  "dispatchStagingDeployment",
  "failExecution",
  "migrationApprovalInbox",
  "myDeploymentRequests",
  "myExecutions",
  "myIssueRequests",
  "myPullRequests",
  "mySchemaMigrationRequests",
  "rejectProductionDeployment",
  "rejectSchemaMigration",
  "requestIssueCreation",
  "requestProductionDeployment",
  "requestPullRequest",
  "requestSchemaMigration",
  "requestStagingDeployment",
].sort();

const expectedScopedEntities = [
  "AgentCredentialMetadata",
  "Allowance",
  "Approval",
  "Connector",
  "Delegation",
  "DeploymentRequest",
  "Environment",
  "Execution",
  "IssueRequest",
  "Principal",
  "PullRequest",
  "Repository",
  "SchemaMigrationRequest",
].sort();

describe("generated tenant-confinement evidence", () => {
  it("covers every declared tenant-owned entity", () => {
    expect(ir.tenant).toBeDefined();

    const entityNames = new Map(ir.entities.map((entity) => [entity.id, entity.name]));
    const scopedNames = ir.tenant!.scopedEntities
      .map(({ entityId }) => entityNames.get(entityId))
      .sort();

    expect(scopedNames).toEqual(expectedScopedEntities);
    expect(entityNames.get(ir.tenant!.entityId)).toBe("Organization");
  });

  it("compile-checks every public operation without a tenant exemption", () => {
    expect(operations.operations.map(({ name }) => name).sort()).toEqual(expectedOperations);

    const compiled = new Map(
      [...ir.actions, ...ir.queries].map((operation) => [operation.id, operation]),
    );

    for (const operation of operations.operations) {
      const irOperation = compiled.get(operation.id);
      expect(irOperation, `${operation.name} is absent from canonical IR`).toBeDefined();
      expect(irOperation?.tenantOpen, `${operation.name} bypasses tenant confinement`).not.toBe(true);
      expect(operation.caller.source, `${operation.name} is not caller-bound`).toBe(
        "authenticatedContext",
      );
      expect(operation.caller.requestSupplied, `${operation.name} accepts caller identity`).toBe(
        false,
      );
      expect(irOperation?.callerParameterId).toBeTruthy();
    }

    const exemptions = enforcement.enforcement.filter(({ id }) =>
      id.startsWith("tenant-exemption:"),
    );
    expect(exemptions).toEqual([]);
  });
});
