// No inference, uploads, instances, imports, database writes, or credential output.
// Default: environment names/presence only. --public-catalog: public metadata GET.
// --check-access: authenticated read-only GETs to the official Nebius endpoints.
// --image UUID additionally checks an already-existing Sandbox image.
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    "public-catalog": { type: "boolean", default: false },
    "check-access": { type: "boolean", default: false },
    image: { type: "string" },
    help: { type: "boolean", default: false },
  },
});

if (values.help) {
  process.stdout.write("Usage: node scripts/provider-readiness.mjs [--public-catalog] [--check-access [--image UUID]]\nNo inference or Sandbox creation is performed. Credentials are never printed.\n");
  process.exit(0);
}
if (values.image && (!values["check-access"] || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(values.image))) {
  throw new Error("--image requires --check-access and an existing Sandbox image UUID, not an OCI digest or tag");
}

const required = [
  "NEBIUS_API_KEY",
  "NEBIUS_AI_PROJECT",
  "DATABASE_URL",
  "SIGNALBOX_AGENT_CONFIG_PATH",
  "SIGNALBOX_MCP_URL",
  "SIGNALBOX_AGENT_TOKEN",
  "SIGNALBOX_OBJECT_BUCKET",
  "SIGNALBOX_OBJECT_REGION",
];
const optional = [
  "SIGNALBOX_OBJECT_ENDPOINT",
  "SIGNALBOX_OBJECT_ACCESS_KEY_ID",
  "SIGNALBOX_OBJECT_SECRET_ACCESS_KEY",
  "SIGNALBOX_OBJECT_FORCE_PATH_STYLE",
  "SIGNALBOX_OBJECT_PREFIX",
  "AWS_ACCESS_KEY_ID",
  "AWS_SECRET_ACCESS_KEY",
  "AWS_SESSION_TOKEN",
  "AWS_PROFILE",
];
const present = (name) => Object.hasOwn(process.env, name);
const report = {
  mode: "read-only-prerequisites",
  environment: Object.fromEntries([...required, ...optional].map((name) => [name, present(name) ? "set" : "absent"])),
  blockers: required.filter((name) => !present(name)).map((name) => `${name} is absent`),
  checks: {},
  notVerified: [
    "Presence does not validate environment values or credentials.",
    "Database schema/seed, active governance bundle, ready capability bindings, and execution profile must exist in the same organization.",
    "The run manifest content hash, repository bundle content hash, execution profile hash, and model pins must match.",
    "S3 read/write access, MCP authentication, inference generation, and Sandbox command execution are not exercised.",
    "BUNDLE input must contain the pinned branch/tag; current clone uses --branch, not a raw commit SHA.",
    "Use an existing Sandbox image UUID with git, cat, tee, mkdir, and the configured check executable already installed.",
    "Use DISABLED initialization/operation networking and preinstalled dependencies; RESTRICTED_REGISTRIES is not implemented.",
    "Stateful workspace commands use disposable=false to preserve checkpoints; this is not an automatically deleted provider run.",
    "Manifest aggregate inference-token, Sandbox-seconds, and external-effect budgets are not runtime counters; configure provider-side spend/quota limits before a paid run.",
  ],
};
if (present("SIGNALBOX_OBJECT_ACCESS_KEY_ID") !== present("SIGNALBOX_OBJECT_SECRET_ACCESS_KEY")) {
  report.blockers.push("SIGNALBOX_OBJECT_ACCESS_KEY_ID and SIGNALBOX_OBJECT_SECRET_ACCESS_KEY must be configured together");
}

async function getJson(url, headers) {
  const response = await fetch(url, {
    method: "GET",
    headers,
    redirect: "error",
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

async function check(name, perform) {
  try {
    report.checks[name] = await perform();
  } catch (error) {
    // Do not print response bodies, URLs, or arbitrary transport errors containing credentials.
    const status = error instanceof Error && /^HTTP \d{3}$/.test(error.message) ? error.message : "request or response failed";
    report.checks[name] = { status: "unavailable", detail: status };
    report.blockers.push(`${name}: ${status}`);
  }
}

if (values["public-catalog"]) {
  await check("publicCatalog", async () => {
    const rows = await getJson("https://tokenfactory.nebius.com/api/public/models_info");
    if (!Array.isArray(rows)) throw new Error("Invalid public catalog");
    return rows.filter((row) => row.vendor === "nvidia" && /nemotron/i.test(row.name)).flatMap((row) =>
      row.flavors.map((flavor) => ({
        id: flavor.model_id,
        status: row.status,
        maxModelLength: flavor.max_model_len,
        functionCalling: flavor.use_cases.includes("function_calling"),
        reasoning: flavor.use_cases.includes("reasoning"),
        inputPricePerMillionTokens: flavor.input_price_per_million_tokens,
        outputPricePerMillionTokens: flavor.output_price_per_million_tokens,
      })),
    );
  });
}

if (values["check-access"]) {
  if (!process.env.NEBIUS_API_KEY || !process.env.NEBIUS_AI_PROJECT) {
    report.blockers.push("--check-access requires nonempty NEBIUS_API_KEY and NEBIUS_AI_PROJECT");
  } else {
    const authorization = `Bearer ${process.env.NEBIUS_API_KEY}`;
    const project = process.env.NEBIUS_AI_PROJECT;
    const sandboxHeaders = { authorization, project };
    await check("projectCatalog", async () => {
      const catalog = await getJson(`https://api.tokenfactory.nebius.com/v1/models?verbose=true&ai_project_id=${encodeURIComponent(project)}`, { authorization });
      if (!Array.isArray(catalog.data)) throw new Error("Invalid project catalog");
      return catalog.data.filter((model) => /nemotron/i.test(model.id)).map((model) => ({
        id: model.id,
        status: model.status ?? null,
        contextLength: model.context_length ?? null,
        supportedFeatures: model.supported_features ?? null,
        supportedSamplingParameters: model.supported_sampling_parameters ?? null,
        perRequestLimits: model.per_request_limits ?? null,
      }));
    });
    await check("sandboxAccess", async () => {
      const identity = await getJson("https://api.tokenfactory.nebius.com/sandboxes/v1/whoami", sandboxHeaders);
      if (identity.permissions?.spawn !== true) report.blockers.push("Sandbox token does not report spawn permission");
      return { permissions: identity.permissions, limits: identity.limits ?? null };
    });
    if (values.image) {
      await check("sandboxImage", async () => {
        const image = await getJson(`https://api.tokenfactory.nebius.com/sandboxes/v1/inspect/${values.image}/`, sandboxHeaders);
        if (image.uuid !== values.image) throw new Error("Image UUID mismatch");
        return { uuid: image.uuid, accessible: true };
      });
    }
  }
}

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
if (report.blockers.length > 0) process.exitCode = 1;
