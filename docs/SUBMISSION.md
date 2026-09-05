# Signalbox — governed actions for AI agents

Signalbox checks an agent's proposed action against current policy before a worker can act on connected systems. A refusal becomes structured feedback the agent can use to choose a permitted alternative. Operators can inspect the decision, policy version, transaction, and worker result in one activity view.

## Demonstrated behavior

A real NVIDIA Nemotron Ultra planner and Super operator edited a disposable website in Nebius Sandbox and passed its Python check. Signalbox denied the production request. Nano initially recommended human review; that recommendation did not create an approval request.

We then continued the saved run with an explicitly configured staging alternative. One additional Nano request selected staging. Signalbox independently authorized the staging request, and a worker published the saved patch to a local filesystem destination. The published file matches the recorded SHA-256 digest. This walkthrough shows saved evidence, including the continuation, rather than presenting an uninterrupted live run.

Governance Studio also demonstrated that changing only the active policy changes the same principal's same-input production decision from allowed to denied and back after rollback. A reviewer cannot publish policy. Administrative policy publication is separate from approval of an individual action.

## Implementation

Signalbox exposes a constrained MCP action catalog, stores content-addressed governance bundles, and uses PostgreSQL for authorization and transactional records. ModelLang declares the baseline rules and generates the boundary. Active tenant restrictions supplement mandatory isolation and baseline safety rules. Running agents see current policy on their next invocation; workers reject stale queued authorization and coordinate effects with policy publication through database locks.

Agents hold scoped Signalbox tokens. Downstream connector credentials remain with the host. Transaction idempotency and connector recovery reduce duplicate effects; arbitrary external APIs do not receive a universal exactly-once guarantee.

## Evidence and limits

The local proof used 13 cumulative inference requests and 11 Sandbox commands, including recovery attempts. The approved continuation used one inference request capped at 1,024 output tokens and no additional Sandbox commands. All 77 tests passed; the 17 policy and Studio tests also passed after the evidence-view update. Live continuation verified authorization, dispatch, worker success, and the published file.

See [sanitized evidence](RECOVERY-EVIDENCE.json) and the [walkthrough guide](DEMO-RECORDING.md). Provider responses, original session history, and credentials remain in private local recovery storage. The hosted instance has not received these changes. The proof demonstrates a local staging effect, not a hosted production deployment.
