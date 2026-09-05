-- Apply using installPolicyGuards: trusted baseline metadata must be supplied on
-- this dedicated installer connection. Generated SQL is never edited or parsed.
BEGIN;
GRANT USAGE, CREATE ON SCHEMA signalbox_architecture TO modellang_owner;
GRANT SELECT ON signalbox_architecture.governance_bundle, signalbox_architecture.object_artifact TO modellang_owner;
GRANT REFERENCES ON signalbox_architecture.governance_bundle TO modellang_owner;
DO $database_grant$
BEGIN
  EXECUTE pg_catalog.format('GRANT CREATE ON DATABASE %I TO modellang_owner', pg_catalog.current_database());
END
$database_grant$;
SET LOCAL ROLE modellang_owner;

CREATE TABLE IF NOT EXISTS signalbox_architecture.installed_policy (
  bundle_id uuid PRIMARY KEY REFERENCES signalbox_architecture.governance_bundle(id),
  org_id uuid NOT NULL,
  schema_name text NOT NULL CHECK (schema_name ~ '^sb_policy_[0-9a-f]{48}$')
);
REVOKE ALL ON signalbox_architecture.installed_policy FROM PUBLIC, modellang_app, modellang_gateway;

CREATE TABLE signalbox_architecture.policy_runtime_installation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  baseline_source_hash text NOT NULL CHECK (baseline_source_hash ~ '^sha256:[0-9a-f]{64}$'),
  function_count integer NOT NULL CHECK (function_count > 0)
);
CREATE TABLE signalbox_architecture.policy_runtime_function (
  function_identity text PRIMARY KEY,
  definition_hash text NOT NULL CHECK (definition_hash ~ '^[0-9a-f]{64}$')
);
REVOKE ALL ON signalbox_architecture.policy_runtime_installation,
  signalbox_architecture.policy_runtime_function FROM PUBLIC, modellang_app, modellang_gateway;

CREATE TABLE signalbox_architecture.policy_action_evidence (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  org_id uuid NOT NULL,
  principal_id uuid NOT NULL,
  operation_id text NOT NULL,
  decision text NOT NULL,
  policy_bundle_id uuid REFERENCES signalbox_architecture.governance_bundle(id),
  policy_source_hash text,
  command_receipt_id bigint REFERENCES model_signalbox_internal.command_receipt(id),
  baseline_expected_revision text,
  policy_expected_revision text,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (command_receipt_id)
);
CREATE INDEX policy_action_evidence_tenant_time
  ON signalbox_architecture.policy_action_evidence(org_id, created_at DESC, id);
REVOKE ALL ON signalbox_architecture.policy_action_evidence FROM PUBLIC, modellang_app, modellang_gateway;

CREATE FUNCTION signalbox_architecture.current_policy_context()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_principal uuid;
  v_org uuid;
  v_locked_org uuid;
  v_bundle uuid;
  v_source text;
  v_schema text;
BEGIN
  -- READ COMMITTED is essential: after waiting for an activation transaction the
  -- next statement must see its committed policy, not a repeatable-read snapshot.
  IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '25001', MESSAGE = 'SB_POLICY_READ_COMMITTED_REQUIRED';
  END IF;
  SELECT principal_id INTO STRICT v_principal FROM model_signalbox_internal.resolve_principal();
  SELECT org_id INTO STRICT v_org FROM model_signalbox.principal WHERE id = v_principal;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text, 0));
  SELECT org_id INTO STRICT v_locked_org FROM model_signalbox.principal WHERE id = v_principal FOR SHARE;
  IF v_org IS DISTINCT FROM v_locked_org THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'SB_POLICY_PRINCIPAL_CHANGED';
  END IF;
  SELECT bundle.id, bundle.source_hash, installed.schema_name INTO v_bundle, v_source, v_schema
  FROM signalbox_architecture.governance_bundle AS bundle
  LEFT JOIN signalbox_architecture.installed_policy AS installed
    ON installed.bundle_id = bundle.id AND installed.org_id = bundle.org_id
  WHERE bundle.org_id = v_org AND bundle.status = 'ACTIVE';
  RETURN pg_catalog.jsonb_build_object('principalId', v_principal, 'orgId', v_org,
    'policyBundleId', v_bundle, 'policySourceHash', v_source, 'schemaName', v_schema);
END
$signalbox$;

CREATE FUNCTION signalbox_architecture.combine_policy_decisions(
  p_operation_id text, p_context jsonb, p_baseline jsonb, p_tenant jsonb,
  p_expected_revision text, p_baseline_only boolean
)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_decision jsonb;
  v_revision text;
BEGIN
  IF p_baseline->>'applicable' IS DISTINCT FROM 'true' THEN
    v_decision := p_baseline;
  ELSIF NOT p_baseline_only AND p_context->>'schemaName' IS NULL THEN
    v_decision := pg_catalog.jsonb_build_object('operationId', p_operation_id,
      'status', 'denied', 'applicable', false, 'authority', 'none',
      'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'signalbox:active_policy_required'));
  ELSIF NOT p_baseline_only AND p_tenant->>'applicable' IS DISTINCT FROM 'true' THEN
    v_decision := p_tenant;
  ELSE
    v_revision := CASE WHEN p_baseline_only THEN p_baseline->>'revision' ELSE
      'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_array(
        p_context->>'policyBundleId', p_context->>'policySourceHash',
        p_baseline->>'revision', p_tenant->>'revision')::text) END;
    v_decision := p_baseline || pg_catalog.jsonb_build_object('revision', v_revision);
    IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
      v_decision := v_decision || pg_catalog.jsonb_build_object('status', 'stale', 'applicable', false,
        'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:' || p_operation_id));
    END IF;
  END IF;
  RETURN v_decision || pg_catalog.jsonb_build_object(
    'policyBundleId', p_context->'policyBundleId', 'policySourceHash', p_context->'policySourceHash',
    'baselineSourceHash', p_baseline->'baselineSourceHash', 'baselineRevision', p_baseline->'revision');
END
$signalbox$;

CREATE FUNCTION signalbox_architecture.assert_policy_decision(p_decision jsonb)
RETURNS void LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $signalbox$
BEGIN
  IF p_decision->>'applicable' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION USING
      ERRCODE = CASE p_decision->>'status' WHEN 'stale' THEN '40001' WHEN 'notApplicable' THEN 'P0001' ELSE '42501' END,
      MESSAGE = CASE p_decision->>'status' WHEN 'stale' THEN 'ML_STALE:' WHEN 'notApplicable' THEN 'ML_PRECONDITION:' ELSE 'ML_AUTHORIZATION:' END
        || COALESCE(p_decision#>>'{explanation,ruleId}', 'signalbox:active_policy_required'),
      DETAIL = p_decision::text;
  END IF;
END
$signalbox$;

CREATE FUNCTION signalbox_architecture.action_evidence(p_issuer text, p_subject text, p_limit integer DEFAULT 100)
RETURNS TABLE(id text, operation_id text, decision text, policy_bundle_id uuid,
  policy_source_hash text, created_at timestamptz, result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE v_org uuid;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  SELECT principal.org_id INTO v_org
  FROM model_signalbox_internal.gateway_principal_binding AS binding
  JOIN model_signalbox.principal AS principal ON principal.id = binding.principal_id
  WHERE binding.issuer = p_issuer AND binding.subject = p_subject
    AND principal.status = 'ACTIVE' AND principal.kind = 'HUMAN';
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_ACTIVITY_HUMAN_REQUIRED';
  END IF;
  RETURN QUERY SELECT evidence.id::text, evidence.operation_id, evidence.decision,
    evidence.policy_bundle_id, evidence.policy_source_hash, evidence.created_at,
    evidence.result || CASE WHEN execution.id IS NULL THEN '{}'::jsonb ELSE
      pg_catalog.jsonb_build_object('execution', pg_catalog.jsonb_build_object(
        'id', execution.id, 'status', execution.status, 'requestId', execution.request_id,
        'externalReference', execution.external_reference)) END
  FROM signalbox_architecture.policy_action_evidence AS evidence
  LEFT JOIN model_signalbox.execution AS execution
    ON execution.org_id = evidence.org_id AND execution.id::text = evidence.result->>'id'
    AND evidence.result->>'kind' = 'action'
    AND evidence.operation_id IN (
      'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'action:act_3e99da927be642efac3d1bee026ef00a',
      'action:act_3e26a4d454634bf3a2058204146d7c45', 'action:act_4a9421bfc2e744969b9f73109e6cda54',
      'action:act_70d3862584094631aca61e9db664d991', 'action:act_5be24324b68d4c2eb334732b36e1b16c',
      'action:act_926686163a6544e79d44dea9336d2c88')
  WHERE evidence.org_id = v_org
  ORDER BY evidence.created_at DESC, evidence.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200);
END
$signalbox$;

-- Only catalog-identified functions are renamed. Bodies, signatures, defaults,
-- receipts, provenance and effects of the compiler-generated baseline are intact.
DO $install$
DECLARE
  v_metadata jsonb := NULLIF(pg_catalog.current_setting('signalbox.policy_guard_metadata', true), '')::jsonb;
  v_item jsonb;
  v_lock jsonb;
  v_action pg_catalog.pg_proc%ROWTYPE;
  v_decide pg_catalog.pg_proc%ROWTYPE;
  v_action_name text;
  v_decide_name text;
  v_operation text;
  v_base_only boolean;
  v_call text;
  v_tenant_args text;
  v_locks text;
  v_body text;
  v_grantee record;
  v_count integer;
BEGIN
  IF pg_catalog.jsonb_typeof(v_metadata) IS DISTINCT FROM 'array' OR pg_catalog.jsonb_array_length(v_metadata) = 0 THEN
    RAISE EXCEPTION 'SB_POLICY_BASELINE_METADATA_REQUIRED';
  END IF;
  SELECT count(*) INTO v_count FROM pg_catalog.pg_proc
  WHERE pronamespace = 'model_signalbox'::regnamespace AND proname LIKE 'decide_act_%';
  IF v_count <> pg_catalog.jsonb_array_length(v_metadata) THEN
    RAISE EXCEPTION 'SB_POLICY_BASELINE_METADATA_INCOMPLETE';
  END IF;
  FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(v_metadata) LOOP
    v_action_name := v_item->>'actionName';
    v_decide_name := v_item->>'decisionName';
    v_operation := v_item->>'operationId';
    v_base_only := v_action_name IN ('complete_execution', 'fail_execution');
    SELECT * INTO STRICT v_action FROM pg_catalog.pg_proc
    WHERE pronamespace = 'model_signalbox'::regnamespace AND proname = v_action_name AND prokind = 'f';
    SELECT * INTO STRICT v_decide FROM pg_catalog.pg_proc
    WHERE pronamespace = 'model_signalbox'::regnamespace AND proname = v_decide_name AND prokind = 'f';
    IF v_action.prorettype <> 'jsonb'::regtype OR v_decide.prorettype <> 'jsonb'::regtype
      OR NOT v_action.prosecdef OR NOT v_decide.prosecdef
      OR v_action.proargmodes IS NOT NULL OR v_decide.proargmodes IS NOT NULL
      OR v_decide.pronargs <> v_action.pronargs + 1
      OR v_decide.proargtypes[v_action.pronargs] <> 'text'::regtype
      OR pg_catalog.to_jsonb(v_action.proargnames) <> v_item->'parameters'
      OR v_decide_name <> 'decide_' || pg_catalog.substr(v_operation, 8)
      OR EXISTS (SELECT 1 FROM pg_catalog.generate_series(0, v_action.pronargs - 1) AS i
        WHERE v_action.proargtypes[i] <> v_decide.proargtypes[i]) THEN
      RAISE EXCEPTION 'SB_POLICY_UNSUPPORTED_SIGNATURE:%', v_operation;
    END IF;
    SELECT pg_catalog.string_agg(pg_catalog.format('%I', name), ', ' ORDER BY ordinal),
      pg_catalog.string_agg(pg_catalog.format('$%s::%s', ordinal, pg_catalog.format_type(v_action.proargtypes[ordinal::integer - 1], NULL)), ', ' ORDER BY ordinal)
    INTO v_call, v_tenant_args
    FROM pg_catalog.unnest(v_action.proargnames) WITH ORDINALITY AS argument(name, ordinal);
    v_locks := '';
    FOR v_lock IN SELECT value FROM pg_catalog.jsonb_array_elements(v_item->'locks') LOOP
      IF v_lock->>'mode' NOT IN ('share', 'update')
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class WHERE relnamespace = 'model_signalbox'::regnamespace
          AND relname = v_lock->>'table' AND relkind = 'r')
        OR (v_lock->>'parameter' IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.unnest(v_action.proargnames) WITH ORDINALITY AS argument(name, ordinal)
          WHERE name = v_lock->>'parameter' AND v_action.proargtypes[ordinal::integer - 1] = 'uuid'::regtype)) THEN
        RAISE EXCEPTION 'SB_POLICY_UNSUPPORTED_LOCK:%', v_operation;
      END IF;
      v_locks := v_locks || pg_catalog.format('PERFORM id FROM model_signalbox.%I WHERE id = %s ORDER BY id FOR %s;',
        v_lock->>'table', CASE WHEN v_lock->>'parameter' IS NULL THEN '(v_context->>''principalId'')::uuid'
          ELSE pg_catalog.format('%I', v_lock->>'parameter') END,
        CASE v_lock->>'mode' WHEN 'share' THEN 'SHARE' ELSE 'UPDATE' END);
    END LOOP;
    -- Revoke every explicit inherited execute grant, not only known role names.
    FOR v_grantee IN SELECT DISTINCT acl.grantee, roles.rolname
      FROM pg_catalog.aclexplode(COALESCE(v_action.proacl, pg_catalog.acldefault('f', v_action.proowner))
        || COALESCE(v_decide.proacl, pg_catalog.acldefault('f', v_decide.proowner))) AS acl
      LEFT JOIN pg_catalog.pg_roles AS roles ON roles.oid = acl.grantee
      WHERE acl.grantee <> v_action.proowner
    LOOP
      EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM %s', v_action.oid::regprocedure,
        CASE WHEN v_grantee.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.quote_ident(v_grantee.rolname) END);
      EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM %s', v_decide.oid::regprocedure,
        CASE WHEN v_grantee.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.quote_ident(v_grantee.rolname) END);
    END LOOP;
    EXECUTE pg_catalog.format('ALTER FUNCTION %s RENAME TO %I', v_action.oid::regprocedure, 'baseline_' || v_action_name);
    EXECUTE pg_catalog.format('ALTER FUNCTION %s RENAME TO %I', v_decide.oid::regprocedure, 'baseline_' || v_decide_name);

    v_body := pg_catalog.format($wrapper$
DECLARE v_context jsonb; v_baseline jsonb; v_tenant jsonb; v_decision jsonb;
BEGIN
  v_context := signalbox_architecture.current_policy_context();
  %s
  v_baseline := model_signalbox.%I(%s, NULL::text) || pg_catalog.jsonb_build_object('baselineSourceHash', %L);
  IF NOT %L::boolean AND v_context->>'schemaName' IS NOT NULL AND v_baseline->>'applicable' = 'true' THEN
    EXECUTE pg_catalog.format('SELECT %%I.%%I(%s, NULL::text)', v_context->>'schemaName', %L)
      INTO v_tenant USING %s;
  END IF;
  v_decision := signalbox_architecture.combine_policy_decisions(%L, v_context, v_baseline, v_tenant, p_expected_revision, %L);
  INSERT INTO signalbox_architecture.policy_action_evidence(org_id, principal_id, operation_id,
    decision, policy_bundle_id, policy_source_hash, result)
  VALUES ((v_context->>'orgId')::uuid, (v_context->>'principalId')::uuid, %L,
    v_decision->>'status', (v_context->>'policyBundleId')::uuid, v_context->>'policySourceHash',
    (v_decision - 'baselineRevision') || pg_catalog.jsonb_build_object('kind', 'assessment'));
  RETURN v_decision;
END
$wrapper$, v_locks, 'baseline_' || v_decide_name, v_call, v_item->>'baselineSourceHash', v_base_only, v_tenant_args,
      v_decide_name, v_call, v_operation, v_base_only, v_operation);
    EXECUTE pg_catalog.format('CREATE FUNCTION model_signalbox.%I(%s) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS %L',
      v_decide_name, pg_catalog.pg_get_function_arguments(v_decide.oid), v_body);

    v_body := pg_catalog.format($wrapper$
DECLARE
  v_context jsonb; v_decision jsonb; v_result jsonb;
  v_expected text := NULLIF(pg_catalog.current_setting('modellang.expected_revision', true), '');
  v_key text := NULLIF(pg_catalog.current_setting('modellang.idempotency_key', true), '');
  v_receipt bigint; v_replay_bundle uuid; v_baseline_expected text; v_replay_expected text;
BEGIN
  v_context := signalbox_architecture.current_policy_context();
  SELECT receipt.id, evidence.policy_bundle_id, evidence.baseline_expected_revision, evidence.policy_expected_revision
  INTO v_receipt, v_replay_bundle, v_baseline_expected, v_replay_expected
  FROM model_signalbox_internal.command_receipt AS receipt
  LEFT JOIN signalbox_architecture.policy_action_evidence AS evidence ON evidence.command_receipt_id = receipt.id
  WHERE receipt.principal_id = (v_context->>'principalId')::uuid AND receipt.action_id = %L
    AND receipt.idempotency_key = v_key AND receipt.status = 'executed';
  IF v_receipt IS NOT NULL AND (%L::boolean OR (
    v_context->>'schemaName' IS NOT NULL AND v_replay_bundle = (v_context->>'policyBundleId')::uuid)) THEN
    -- Baseline verifies fingerprint/options and returns its immutable stored result.
    IF v_replay_expected IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:' || %L;
    END IF;
    PERFORM pg_catalog.set_config('modellang.expected_revision', COALESCE(v_baseline_expected, ''), true);
    RETURN model_signalbox.%I(%s);
  END IF;
  IF v_receipt IS NOT NULL THEN
    PERFORM signalbox_architecture.assert_policy_decision(pg_catalog.jsonb_build_object(
      'status', 'denied', 'applicable', false, 'policyBundleId', v_context->'policyBundleId',
      'policySourceHash', v_context->'policySourceHash',
      'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'signalbox:policy_changed_replay')));
  END IF;
  v_decision := model_signalbox.%I(%s, v_expected);
  PERFORM signalbox_architecture.assert_policy_decision(v_decision);
  v_baseline_expected := CASE WHEN v_expected IS NULL THEN NULL ELSE v_decision->>'baselineRevision' END;
  PERFORM pg_catalog.set_config('modellang.expected_revision', COALESCE(v_baseline_expected, ''), true);
  v_result := model_signalbox.%I(%s);
  SELECT id INTO v_receipt FROM model_signalbox_internal.command_receipt
  WHERE principal_id = (v_context->>'principalId')::uuid AND action_id = %L AND idempotency_key = v_key;
  INSERT INTO signalbox_architecture.policy_action_evidence(org_id, principal_id, operation_id,
    decision, policy_bundle_id, policy_source_hash, command_receipt_id, baseline_expected_revision, policy_expected_revision, result)
  VALUES ((v_context->>'orgId')::uuid, (v_context->>'principalId')::uuid, %L, 'executed',
    (v_context->>'policyBundleId')::uuid, v_context->>'policySourceHash', v_receipt, v_baseline_expected, v_expected,
    pg_catalog.jsonb_build_object('kind', 'action', 'id', v_result->'id', 'status', v_result->'status',
      'baselineSourceHash', v_decision->'baselineSourceHash'));
  RETURN v_result;
END
$wrapper$, v_operation, v_base_only, v_operation, 'baseline_' || v_action_name, v_call, v_decide_name, v_call,
      'baseline_' || v_action_name, v_call, v_operation, v_operation);
    EXECUTE pg_catalog.format('CREATE FUNCTION model_signalbox.%I(%s) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS %L',
      v_action_name, pg_catalog.pg_get_function_arguments(v_action.oid), v_body);
    EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION model_signalbox.%I(%s) FROM PUBLIC', v_action_name, pg_catalog.pg_get_function_identity_arguments(v_action.oid));
    EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION model_signalbox.%I(%s) FROM PUBLIC', v_decide_name, pg_catalog.pg_get_function_identity_arguments(v_decide.oid));
    EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION model_signalbox.%I(%s) TO modellang_app', v_action_name, pg_catalog.pg_get_function_identity_arguments(v_action.oid));
    EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION model_signalbox.%I(%s) TO modellang_app', v_decide_name, pg_catalog.pg_get_function_identity_arguments(v_decide.oid));
  END LOOP;
END
$install$;

-- Worker confirmation is a pre-effect authorization check, not an execution
-- record. The caller must retain this transaction through the connector effect.
ALTER FUNCTION model_signalbox_worker.confirm_execution_claim(text, text, text, uuid, uuid)
  RENAME TO baseline_confirm_execution_claim;
REVOKE ALL ON FUNCTION model_signalbox_worker.baseline_confirm_execution_claim(text, text, text, uuid, uuid)
  FROM PUBLIC, modellang_app, modellang_gateway;
CREATE FUNCTION model_signalbox_worker.confirm_execution_claim(
  p_issuer text, p_subject text, p_worker_id text, p_execution_id uuid, p_claim_token uuid
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE v_context jsonb;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  PERFORM model_signalbox_internal.bind_gateway_identity(p_issuer, p_subject);
  v_context := signalbox_architecture.current_policy_context();
  PERFORM 1 FROM model_signalbox.execution AS execution
  JOIN model_signalbox.connector AS connector ON connector.id = execution.connector_id
  JOIN model_signalbox_worker.execution_claim AS claim ON claim.execution_id = execution.id
  WHERE execution.id = p_execution_id AND execution.org_id = (v_context->>'orgId')::uuid
  FOR SHARE OF execution, connector, claim;
  IF NOT EXISTS (SELECT 1 FROM model_signalbox_worker.execution_claim
    WHERE execution_id = p_execution_id AND claim_token = p_claim_token
      AND worker_id = p_worker_id AND leased_until > pg_catalog.clock_timestamp()) THEN RETURN false; END IF;
  IF v_context->>'schemaName' IS NULL OR NOT model_signalbox_worker.baseline_confirm_execution_claim(
    p_issuer, p_subject, p_worker_id, p_execution_id, p_claim_token) THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM model_signalbox_internal.action_audit AS audit
    JOIN signalbox_architecture.policy_action_evidence AS evidence ON evidence.command_receipt_id = audit.command_receipt_id
    WHERE audit.target_id = p_execution_id AND evidence.org_id = (v_context->>'orgId')::uuid
      AND evidence.policy_bundle_id = (v_context->>'policyBundleId')::uuid AND evidence.decision = 'executed'
      AND audit.action_id IN ('action:act_cbb72fd307704ab3927aa4bea8112fbf', 'action:act_3e99da927be642efac3d1bee026ef00a',
        'action:act_3e26a4d454634bf3a2058204146d7c45', 'action:act_4a9421bfc2e744969b9f73109e6cda54',
        'action:act_70d3862584094631aca61e9db664d991')
  );
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_worker.confirm_execution_claim(text, text, text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION model_signalbox_worker.confirm_execution_claim(text, text, text, uuid, uuid) TO modellang_gateway;

REVOKE ALL ON FUNCTION signalbox_architecture.current_policy_context() FROM PUBLIC, modellang_app, modellang_gateway;
REVOKE ALL ON FUNCTION signalbox_architecture.combine_policy_decisions(text, jsonb, jsonb, jsonb, text, boolean) FROM PUBLIC, modellang_app, modellang_gateway;
REVOKE ALL ON FUNCTION signalbox_architecture.assert_policy_decision(jsonb) FROM PUBLIC, modellang_app, modellang_gateway;
REVOKE ALL ON FUNCTION signalbox_architecture.action_evidence(text, text, integer) FROM PUBLIC, modellang_app;
GRANT EXECUTE ON FUNCTION signalbox_architecture.action_evidence(text, text, integer) TO modellang_gateway;

-- Startup integrity check: a new host must not expose Studio against an old DB,
-- or one where reapplying generated SQL accidentally replaced policy wrappers.
CREATE FUNCTION signalbox_architecture.assert_policy_runtime(p_expected_source_hash text)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE v_installation signalbox_architecture.policy_runtime_installation%ROWTYPE;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  SELECT * INTO v_installation FROM signalbox_architecture.policy_runtime_installation WHERE singleton;
  IF NOT FOUND OR v_installation.baseline_source_hash IS DISTINCT FROM p_expected_source_hash
    OR v_installation.function_count <> (SELECT count(*) FROM signalbox_architecture.policy_runtime_function) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'SB_POLICY_RUNTIME_NOT_INSTALLED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM signalbox_architecture.policy_runtime_function AS registered
    LEFT JOIN pg_catalog.pg_proc AS implementation
      ON implementation.oid = pg_catalog.to_regprocedure(registered.function_identity)
    WHERE implementation.oid IS NULL OR implementation.proowner <> 'modellang_owner'::regrole
      OR registered.definition_hash IS DISTINCT FROM pg_catalog.encode(pg_catalog.sha256(
        pg_catalog.convert_to(pg_catalog.pg_get_functiondef(implementation.oid), 'UTF8')), 'hex')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'SB_POLICY_RUNTIME_CHANGED';
  END IF;
END
$signalbox$;
REVOKE ALL ON FUNCTION signalbox_architecture.assert_policy_runtime(text) FROM PUBLIC, modellang_app;
GRANT EXECUTE ON FUNCTION signalbox_architecture.assert_policy_runtime(text) TO modellang_gateway;

DO $register_runtime$
DECLARE v_metadata jsonb := pg_catalog.current_setting('signalbox.policy_guard_metadata')::jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(v_metadata) AS item
    WHERE item->>'baselineSourceHash' IS DISTINCT FROM v_metadata->0->>'baselineSourceHash') THEN
    RAISE EXCEPTION 'SB_POLICY_BASELINE_METADATA_HASH_MISMATCH';
  END IF;
  INSERT INTO signalbox_architecture.policy_runtime_function(function_identity, definition_hash)
  SELECT implementation.oid::regprocedure::text, pg_catalog.encode(pg_catalog.sha256(
    pg_catalog.convert_to(pg_catalog.pg_get_functiondef(implementation.oid), 'UTF8')), 'hex')
  FROM pg_catalog.pg_proc AS implementation
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = implementation.pronamespace
  WHERE (namespace.nspname = 'model_signalbox' AND EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_array_elements(v_metadata) AS item
    WHERE implementation.proname IN (item->>'actionName', item->>'decisionName',
      'baseline_' || (item->>'actionName'), 'baseline_' || (item->>'decisionName'))
  )) OR (namespace.nspname = 'model_signalbox_worker'
    AND implementation.proname IN ('confirm_execution_claim', 'baseline_confirm_execution_claim'))
    OR (namespace.nspname = 'signalbox_architecture' AND implementation.proname IN (
      'current_policy_context', 'combine_policy_decisions', 'assert_policy_decision',
      'action_evidence', 'assert_policy_runtime'));
  INSERT INTO signalbox_architecture.policy_runtime_installation(baseline_source_hash, function_count)
  SELECT v_metadata->0->>'baselineSourceHash', count(*) FROM signalbox_architecture.policy_runtime_function;
END
$register_runtime$;
COMMIT;
