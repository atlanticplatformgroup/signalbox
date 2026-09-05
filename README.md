# Signalbox

Signalbox puts an independently enforced boundary between an AI agent and the systems it acts on. An agent proposes an action; Signalbox checks the current policy, returns a structured decision, and lets a worker execute authorized requests through controlled connectors.

Agents hold scoped Signalbox tokens rather than downstream connector credentials. Their tool catalog is constrained, and each invocation is assessed against its actual input. A denial lets the host and agent choose a permitted alternative or stop for human review; it never grants additional authority.

Governance Studio opens on recorded actions and their policy versions. An administrator can inspect, compile, activate, and roll back additional restrictions on Signalbox's existing operations. [ModelLang](https://github.com/atlanticplatformgroup/ModelLang) declares those rules and generates the PostgreSQL authorization boundary. Tenant isolation and baseline safety rules remain mandatory.

## How it works

1. An authorized human administrator activates a versioned policy in Governance Studio. Permission to approve an action is separate from permission to publish policy.
2. Signalbox stores the source and compiled governance bundle as content-addressed objects, with PostgreSQL as the transactional authority.
3. An agent connects over MCP. Every invocation checks the current active policy, including requests from agents that started before a policy change.
4. A worker executes authorized requests through controlled connectors for GitHub, static-site deployment, and PostgreSQL migrations. Stale queued work is rejected; publication waits while a worker holds the policy lock during an effect.

Decisions and model transactions are distinct from external effects. The activity view shows a worker's recorded status and external reference when available. Idempotency and connector recovery reduce duplicate effects; this is not a universal exactly-once guarantee for arbitrary external APIs.

The isolated local demonstration verified a real agent production denial, a continued Nano staging correction, and a worker filesystem effect. See the [evidence](docs/RECOVERY-EVIDENCE.json) and [submission draft](docs/SUBMISSION.md). The [hosted instance](https://143-198-185-50.sslip.io/studio/) now runs these changes. A fresh hosted staging transaction published the same verified artifact; see [hosted release evidence](docs/HOSTED-RELEASE-EVIDENCE.json). See [release evidence](docs/RECOVERY-EVIDENCE.json) for the verified checkpoint.

## Nebius and NVIDIA

The coding agent runs in a **Nebius Token Factory Sandbox** and uses NVIDIA Nemotron open models through the Token Factory inference API. Model assignments are resolved from the live catalog and pinned into each run manifest.

| Role | Model | Purpose |
|---|---|---|
| Planner | `nvidia/Nemotron-3-Ultra-550b-a55b` | Decompose work and identify risks |
| Operator | `nvidia/nemotron-3-super-120b-a12b` | Drive the tool-calling implementation loop |
| Correction | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B` | Turn governance denials into valid next actions |
| Narration | `nvidia/nemotron-3-super-120b-a12b` | Explain the audit timeline to a compliance reader |

## Run locally

Requirements:

- Node.js 22+
- PostgreSQL 16; the installer role needs `CREATEDB` and `CREATEROLE`
- An S3-compatible bucket
- A Nebius API key and AI project to run the agent

Install dependencies, generate the boundary, and initialize an empty database:

```bash
npm install
npm run modellang:check
npm run modellang:build
ADMIN_DATABASE_URL=postgresql://... node scripts/install-database.mjs --seed
```

Configure the server:

```bash
export DATABASE_URL=postgresql://...
export SIGNALBOX_POLICY_DATABASE_URL=postgresql://...
export PUBLIC_ORIGIN=http://127.0.0.1:4310
export SIGNALBOX_OBJECT_BUCKET=signalbox
export SIGNALBOX_OBJECT_REGION=auto
export SIGNALBOX_OBJECT_ENDPOINT=https://<account>.r2.cloudflarestorage.com
export SIGNALBOX_OBJECT_ACCESS_KEY_ID=...
export SIGNALBOX_OBJECT_SECRET_ACCESS_KEY=...
```

Start the boundary and Governance Studio:

```bash
npm start
```

Open `http://127.0.0.1:4310/studio/`. GitHub or OIDC identities must be bound to a Signalbox principal before they receive authority; [`scripts/demo-identity.mjs`](./scripts/demo-identity.mjs) creates a non-admin demo reviewer.

The worker additionally needs `SIGNALBOX_WORKER_ISSUER`, `SIGNALBOX_WORKER_SUBJECT`, and `CONNECTOR_CONFIG_PATH`:

```bash
npm run worker
```

The governed agent additionally needs `NEBIUS_API_KEY`, `NEBIUS_AI_PROJECT`, `SIGNALBOX_AGENT_CONFIG_PATH`, `SIGNALBOX_MCP_URL`, and a token issued by [`scripts/demo-token.mjs`](./scripts/demo-token.mjs):

```bash
npm run agent
```

## Verify

Tests use PostgreSQL 16 directly. Start the expected local container, then run:

```bash
docker run -d --name sb-pg16 \
  -e POSTGRES_USER=nebius_admin \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=sb_managed \
  -p 55433:5432 postgres:16

npm test
npm run verify
```

## Prior work

Signalbox was started during the Nebius Global AI Hackathon. ModelLang is a separate, pre-existing Apache-2.0 compiler maintained by the same author; Signalbox pins version `0.51.0`. The integration findings and upstream compiler fixes are documented in [`SPIKE.md`](./SPIKE.md).

## License

Apache-2.0. See [`LICENSE`](./LICENSE).
