import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { GovernedCodingAgent } from "./agents/runtime.mjs";
import { SandboxWorkspace, TokenFactorySandboxClient, type SandboxCheck } from "./agents/sandbox.mjs";
import { SignalboxMcpTools } from "./agents/signalbox-mcp.mjs";
import { TokenFactoryClient } from "./agents/token-factory.mjs";
import { arrayValue, integerValue, objectValue, optionalString, stringValue } from "./agents/validation.mjs";

const configPath = resolve(requiredEnvironment("SIGNALBOX_AGENT_CONFIG_PATH"));
const config = objectValue(JSON.parse(await readFile(configPath, "utf8")), "agent configuration");
const apiKey = requiredEnvironment("NEBIUS_API_KEY");
const projectId = requiredEnvironment("NEBIUS_AI_PROJECT");
const signalbox = await SignalboxMcpTools.connect({
  url: requiredEnvironment("SIGNALBOX_MCP_URL"),
  accessToken: requiredEnvironment("SIGNALBOX_AGENT_TOKEN"),
  allowedActions: optionalStringArray(config.allowedActions, "allowedActions"),
});

try {
  const inference = new TokenFactoryClient({
    apiKey,
    projectId,
    baseUrl: optionalString(config.tokenFactoryBaseUrl, "tokenFactoryBaseUrl"),
  });
  const models = await inference.discoverModels();
  const sandboxClient = new TokenFactorySandboxClient({
    apiKey,
    projectId,
    baseUrl: optionalString(config.sandboxBaseUrl, "sandboxBaseUrl"),
  });
  const checks = parseChecks(config.checks);
  const sandbox = new SandboxWorkspace({
    client: sandboxClient,
    baseImage: stringValue(config.sandboxImage, "sandboxImage"),
    repositoryUrl: stringValue(config.repositoryUrl, "repositoryUrl"),
    revision: stringValue(config.revision, "revision"),
    checks,
    workspaceRoot: optionalString(config.workspaceRoot, "workspaceRoot"),
    gitExecutable: optionalString(config.gitExecutable, "gitExecutable"),
    catExecutable: optionalString(config.catExecutable, "catExecutable"),
    teeExecutable: optionalString(config.teeExecutable, "teeExecutable"),
    mkdirExecutable: optionalString(config.mkdirExecutable, "mkdirExecutable"),
    maxCommands: optionalInteger(config.maxCommands, "maxCommands"),
    maxWriteBytes: optionalInteger(config.maxWriteBytes, "maxWriteBytes"),
  });
  const stagingFallback = config.stagingFallback === undefined
    ? undefined
    : { input: objectValue(config.stagingFallback, "stagingFallback") };
  const agent = new GovernedCodingAgent({
    inference,
    sandbox,
    governance: signalbox,
    checkNames: checks.map((check) => check.name),
    stagingFallback,
    maxOperatorTurns: optionalInteger(config.maxOperatorTurns, "maxOperatorTurns"),
  });
  const result = await agent.run(stringValue(config.task, "task"));
  process.stdout.write(`${JSON.stringify({ models, ...result }, null, 2)}\n`);
} finally {
  await signalbox.close();
}

function parseChecks(value: unknown): SandboxCheck[] {
  return arrayValue(value, "checks").map((candidate, index) => {
    const check = objectValue(candidate, `checks[${index}]`);
    return {
      name: stringValue(check.name, `checks[${index}].name`),
      executable: stringValue(check.executable, `checks[${index}].executable`),
      args: arrayValue(check.args, `checks[${index}].args`).map((argument, argumentIndex) => stringValue(argument, `checks[${index}].args[${argumentIndex}]`)),
      timeoutSeconds: optionalInteger(check.timeoutSeconds, `checks[${index}].timeoutSeconds`),
    };
  });
}

function optionalStringArray(value: unknown, name: string): string[] | undefined {
  if (value === undefined) return undefined;
  return arrayValue(value, name).map((candidate, index) => stringValue(candidate, `${name}[${index}]`));
}

function optionalInteger(value: unknown, name: string): number | undefined {
  return value === undefined ? undefined : integerValue(value, name);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}
