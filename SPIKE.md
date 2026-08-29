# Signalbox — Phase 0 spike results

**Transactional interlocking for AI agent actions.**

> Identity providers prove who the agent is. Signalbox proves the action is safe to run right now — and commits the decision and the effect together, exactly once.

Spike run 2026-08-29. Target: Nebius x NVIDIA Global AI Hackathon, 2026-10-30 10:00 PDT.
Delivery plan: [PLAN.md](./PLAN.md).

## Purpose

Answer, before committing eight weeks, two questions the plan identified as decisive:

1. **R1** — does the ModelLang-generated PostgreSQL boundary install on managed PostgreSQL, where no superuser login exists?
2. **Model viability** — do the three workarounds forced by ModelLang 0.50's constraints actually hold against the real compiler, and do the four enforcement guarantees hold against a real database?

Both are answered. Both are green.

## Result summary

| Question | Answer | Evidence |
|---|---|---|
| Model compiles | Yes — 8 entities, 4 actions, 2 queries, 1 workflow | `modelc check --strict` OK |
| Installs without superuser | Yes, after three upstream fixes | 8/8 SQL files applied as non-superuser |
| `btree_gist` required | No — no extension is created at all | no `CREATE EXTENSION` in generated SQL |
| Enforcement guarantees | All hold | 20/20 tests against live PostgreSQL 16 |
| Caller identity is unforgeable | Yes — absent from every input type | `RequestProductionDeploymentInput` is `{delegation, environment, commitSha}` |

## R1 — managed PostgreSQL install

**Verdict: resolved. Nebius Managed PostgreSQL 16 is a viable target; no self-managed fallback needed.**

Reproduced by installing into a database owned by a role with `CREATEDB` + `CREATEROLE` and **no** superuser attribute, which is what managed providers grant. Three genuine upstream bugs surfaced, all now fixed in ModelLang and covered by regression tests.

### Bug 1 — `ALTER ROLE ... NOSUPERUSER` requires superuser

`001_roles.sql` opened with the comment *"run as a role with CREATEROLE"* and then failed for exactly such a role:

```
ERROR:  permission denied to alter role
DETAIL:  Only roles with the SUPERUSER attribute may change the SUPERUSER attribute.
```

PostgreSQL rejects any `ALTER ROLE` that *names* the SUPERUSER attribute from a non-superuser, **even when the value is unchanged**. The statements were idempotent re-assertions of attributes `CREATE ROLE` had already set. Fix: drop `NOSUPERUSER` from the `ALTER ROLE` re-assertions. Roles are still created `NOSUPERUSER`; nothing gains privilege.

### Bug 2 — PostgreSQL 16 withholds `SET OPTION` from the installer

With bug 1 fixed, `002_schema.sql` failed on its opening `SET ROLE modellang_owner`:

```
ERROR:  must be able to SET ROLE "modellang_owner"
```

PostgreSQL 16 grants a non-superuser `CREATEROLE` creator membership in the roles it creates, but with `set_option = false`:

```
granted_role   | modellang_owner
member         | nebius_admin
admin_option   | t
inherit_option | f
set_option     | f
```

The installer can administer the role but not assume it. Fix: the bootstrap now re-grants each created role to the installing role `WITH SET TRUE`, guarded so superusers are skipped. The installer already holds `ADMIN OPTION`, so it is entitled to make this grant.

### Bug 3 — generated `tsconfig.build.json` fails under TypeScript 7

```
error TS5011: The common source directory of 'tsconfig.build.json' is './typescript'.
The 'rootDir' setting must be explicitly set...
```

Fix: pin `rootDir: "typescript"`, matching the sole `include` root, which preserves the existing `dist/<file>.js` emit layout that the smoke gate depends on.

### Post-fix verification

Unmodified generated SQL, full teardown, non-superuser install:

```
001_roles.sql          OK      003_queries.sql        OK
002_schema.sql         OK      003_consumers.sql      OK
003_decisions.sql      OK      004_grants.sql         OK
003_actions.sql        OK      005_seed.sql           OK
```

Upstream: 354 ModelLang tests green (301 unit, 53 live-PostgreSQL integration) plus lint, dead-code, agent evaluation, and the clean-install package gate. Two regression tests added to `tests/codegen.test.ts`.

## Model viability — the four workarounds

Each ModelLang 0.50 constraint was worked around without a language change. Three were known from the audit; the fourth was discovered here.

### 1. One principal entity per model
`type-checker.ts:177` — `E2304: All actions and queries must use the same principal entity type.` Separate `HumanPrincipal` and `AgentPrincipal` entities do not compile. Resolved with a single `Principal` entity carrying `kind: PrincipalKind`. Separation of duties becomes `actor.kind == HUMAN and actor != request.requestedBy`, which reads better than the two-entity version.

### 2. No arithmetic → budget as allowance rows
`parser.ts:9-11` — the operator set is `or, and, ==, !=, <, <=, >, >=, in`. No `+`, `-`, `*`, `/` token exists in the lexer. `consumed = consumed + cost` is inexpressible.

Resolved by pre-issuing consumption tokens and making double-spend a storage constraint:

```modellang
entity Execution {
  request: ProductionDeployRequest @unique;
  allowance: Allowance @unique;
}
```

This is stronger than a counter. Unique-index violations are detected regardless of transaction isolation level, so correctness holds at the default `READ COMMITTED` with no `SERIALIZABLE` retry machinery. Budget exhaustion is "no unconsumed allowance exists" — a query, not a comparison.

### 3. No `Json` type → typed per-action request entity
`type-checker.ts:13` — scalars are `String, Int, Decimal, Boolean, UUID, DateTime`, plus `Money<C>`, `Set<Enum>`, and entity references. Resolved with one typed entity per protected action, so the boundary can actually constrain *what* is being deployed rather than storing an opaque blob.

### 4. Invariants are local-only *(new finding)*
`E2406: Entity invariants may not dereference related entities.` Not found in the static audit. Cross-entity tenant consistency such as `agent.org == org` **cannot be an invariant**. This is why `procurement.model` snapshots `approvedByRoles` with `@snapshot` instead of reading `approvedBy.roles`.

Resolved by moving cross-entity org checks into policies and action preconditions, which *can* traverse. Consequence: tenant consistency is enforced at the operation boundary, not at rest. Acceptable because `004_grants.sql` denies application roles direct table writes — and it is precisely the gap ModelLang 0.51 tenant scoping addresses.

### Bonus finding — workflow totality
`E3018: Workflow has unreachable state(s): REJECTED.` The compiler requires every enum state in a workflow's field to be reachable by some transition. This caught a genuinely missing rejection path in the first draft.

## Enforcement — 20/20 against live PostgreSQL 16

Run through the generated gateway executor against the non-superuser-installed database. Nothing mocked.

**Caller identity**
- bound by host, absent from the action input contract — the agent never supplies a principal id, the boundary derives it
- unbound credential rejected

**Delegation scope**
- environment outside the delegation → `AuthorizationError`
- revoked delegation → `AuthorizationError`

**Guarantee A — separation of duties**
- requesting agent approving its own request → `AuthorizationError`
- approver from another organization → `AuthorizationError`
- human lacking `APPROVER` → `AuthorizationError`
- independent human approver admitted, exactly one `Approval` row
- **requester == approver rejected at rest even for a privileged direct writer**, by `ck_production_deploy_request_approver_differs_from_requester`

**Guarantee B — a request executes at most once**
- second execution → `PreconditionError`
- direct privileged insert → `uq_execution_request_id_unique` violation

**Guarantee C — an allowance is consumed at most once**
- same allowance on a second request → rejected; execution count stays 1; the rejected request does not transition
- budget exhausts when every allowance is spent

**Idempotency**
- replay returns one stored result, creates no second request
- same key with different input → `IdempotencyConflictError`
- keys are scoped per principal — one principal cannot replay another's result

**Guarantee D — concurrency**
- two approvers racing one request → exactly one winner
- two executions racing one allowance → exactly one winner

**Tenant isolation**
- reads confined to the caller's organization (1 row vs 0 rows across orgs)

**Audit**
- every executed action records a decision with model provenance

### One taxonomy finding

A unique-constraint violation on an entity-reference field surfaces as **`InvariantError`**, not `ConflictError`. Allowance double-spend therefore maps to HTTP 422 rather than 409. Semantically it is a conflict; worth revisiting upstream, and worth pinning deliberately in Signalbox's HTTP mapping either way.

## Reproducing

```bash
docker run -d --name sb-pg16 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=signalbox -p 55433:5432 postgres:16-alpine

npx modelc check signalbox.model --strict
npx modelc build signalbox.model --out generated/signalbox
# apply generated/signalbox/postgres/*.sql in filename order
psql -f seed.sql
(cd generated/signalbox && npm install --omit=dev && npx tsc -p tsconfig.build.json)
npx vitest run
```

## What this unblocks

Phase 1 can start on schedule with no open stack question:

- **Nebius Managed PostgreSQL 16 is confirmed** as the database. No self-managed fallback, no `btree_gist` dependency.
- The domain model shape is settled — `Principal` + `kind`, allowance rows, typed request entities, cross-entity checks in policies.
- The four guarantees the demo depends on are proven, so the video's failure beats are real rather than staged.
- ModelLang 0.51 tenant scoping is specified in `docs/0.51_TENANT_SCOPING_PLAN.md`, motivated directly by the `E2406` finding.

## Next

1. Ship ModelLang 0.51 tenant scoping, publish, then **freeze the compiler** and pin the exact version.
2. Expand to the full ~14-entity model under `@tenantScoped`.
3. Read the full Nebius official rules for a concurrent-submission clause before planning the Galuxium double-submit.

## Known local-only state

`package.json` declares `@atlanticplatformgroup/modellang` at `0.50.3`, but the three
fixes above are **unreleased** — they exist only in the local ModelLang worktree.
Until a patch is published, install from a local `npm pack` tarball. Publishing the
patch release is a prerequisite for the first reproducible clone of this repo.
