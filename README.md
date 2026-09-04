# Signalbox

Signalbox is a control plane for AI agents that take real actions. Agents receive only the operations they are authorized to use—not raw credentials—and every request, decision, approval, execution, and result is recorded.

Governance rules are written once in [ModelLang](https://github.com/atlanticplatformgroup/ModelLang) and compiled into the PostgreSQL authorization boundary and the MCP tools exposed to agents. A denied action returns a structured reason, allowing an agent to request approval, choose a permitted resource, or stop safely.

```modellang
policy ApiDelegation(actor: Agent, resource: ApiResource) {
  allow active_nonproduction_agent: actor.active and not resource.production;
}

action callApi(caller actor: Agent, resource: ApiResource) -> ApiRequest {
  authorize ApiDelegation(actor, resource);
  idempotency required;
  create ApiRequest { resource = resource; requestedBy = actor; }
}
```

## How it works

1. A human defines and activates a versioned ModelLang policy in Governance Studio.
2. Signalbox stores the source and compiled governance bundle as content-addressed objects, with PostgreSQL as the transactional authority.
3. An agent connects over MCP and sees only its currently authorized operations.
4. A worker executes approved requests through controlled connectors for GitHub, static-site deployment, and PostgreSQL migrations.

The hosted demo is available at [143-198-185-50.sslip.io/studio](https://143-198-185-50.sslip.io/studio/). A reviewer credential is provided with the submission.

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

Tests use a live PostgreSQL 16 instance. With PostgreSQL available at the connection configured by the test environment:

```bash
npm test
npm run verify
```

## Prior work

Signalbox was started during the Nebius Global AI Hackathon. ModelLang is a separate, pre-existing Apache-2.0 compiler maintained by the same author; Signalbox pins version `0.51.0`. The integration findings and upstream compiler fixes are documented in [`SPIKE.md`](./SPIKE.md).

## License

Apache-2.0. See [`LICENSE`](./LICENSE).
