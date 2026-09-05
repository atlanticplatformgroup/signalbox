// Prove Studio publication changes the same agent action, then leave production restricted.
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { Pool } from "pg";
import { createSignalboxGatewayExecutor } from "../generated/signalbox/dist/gateway.js";

const directory = resolve(process.argv[2]);
const config = JSON.parse(await readFile(join(directory, "config.json"), "utf8"));
assert.equal(new URL(config.appOrigin).hostname, "127.0.0.1");
assert.equal(new URL(config.databaseUrl).hostname, "127.0.0.1");
const post = async (path, body, token = config.admin.token) => {
  const response = await fetch(`${config.appOrigin}/studio/api/${path}`, {
    method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
};
const pool = new Pool({ connectionString: config.databaseUrl });
try {
  const executor = createSignalboxGatewayExecutor(pool, config.agent);
  const operation = "action:act_d10d1618ed4045f396b64fc3745ce3dd";
  const input = {
    delegation: "00000000-0000-4000-8000-0000000000f4",
    environment: config.resources.productionEnvironmentId,
    connector: "00000000-0000-4000-8000-0000000000c2", commitSha: "policy-proof-fixed-input",
  };
  const before = await executor.assess(operation, input);
  assert.equal(before.applicable, true);
  const compiled = await post("compile", { source: await readFile(config.restrictedSourcePath, "utf8") });
  assert.equal(compiled.status, 200);
  assert.equal(compiled.body.ok, true);
  const candidateId = compiled.body.candidateId;
  assert.equal(typeof candidateId, "string");
  const reviewer = await post("activate", { candidateId }, config.reviewer.token);
  assert.equal(reviewer.status, 403);
  const activated = await post("activate", { candidateId });
  assert.equal(activated.body.ok, true);
  const restricted = await executor.assess(operation, input);
  assert.equal(restricted.applicable, false);
  assert.equal(restricted.policyBundleId, candidateId);
  const rollback = await post("rollback", {});
  assert.equal(rollback.body.ok, true);
  const restored = await executor.assess(operation, input);
  assert.equal(restored.applicable, true);
  assert.equal(restored.policyBundleId, before.policyBundleId);
  assert.equal((await post("activate", { candidateId })).body.ok, true);
  const final = await executor.assess(operation, input);
  assert.equal(final.applicable, false);
  const evidence = { operation, input, before, restricted, restored, final, reviewerActivationStatus: reviewer.status };
  await writeFile(join(directory, "policy-proof.json"), JSON.stringify(evidence, null, 2), { mode: 0o600 });
  console.log("PROVEN: identical input allowed, denied after publication, allowed after rollback; reviewer publication rejected. Production left restricted.");
} finally {
  await pool.end();
}
