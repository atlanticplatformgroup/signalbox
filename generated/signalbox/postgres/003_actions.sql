-- Generated guarded action functions. Caller identity is resolved from direct login or transaction-bound gateway context.
SET ROLE modellang_owner;

CREATE OR REPLACE FUNCTION "model_signalbox"."request_production_deployment"("p_delegation" uuid, "p_environment" uuid, "p_commit_sha" text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_identity_issuer text;
  v_identity_subject text;
  v_revision text;
  v_expected_revision text;
  v_idempotency_key text;
  v_correlation_id text;
  v_causation_id text;
  v_request_hash text;
  v_receipt_source_hash text;
  v_receipt_request_hash text;
  v_receipt_status text;
  v_receipt_id bigint;
  v_action_audit_id bigint;
  v_receipt_response jsonb;
  v_response jsonb;
  v_authority_policy_id text;
  v_authority_id text;
  v_result "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_environment "model_signalbox"."environment"%ROWTYPE;
  v_environment_xmin text;
BEGIN
  SELECT identity."principal_id", identity."identity_issuer", identity."identity_subject"
  INTO v_principal_id, v_identity_issuer, v_identity_subject
  FROM "model_signalbox_internal"."resolve_principal"() AS identity;

  v_expected_revision := NULLIF(pg_catalog.current_setting('modellang.expected_revision', true), '');
  v_idempotency_key := NULLIF(pg_catalog.current_setting('modellang.idempotency_key', true), '');
  v_correlation_id := NULLIF(pg_catalog.current_setting('modellang.correlation_id', true), '');
  v_causation_id := NULLIF(pg_catalog.current_setting('modellang.causation_id', true), '');
  PERFORM pg_catalog.set_config('modellang.expected_revision', '', true);
  PERFORM pg_catalog.set_config('modellang.idempotency_key', '', true);
  PERFORM pg_catalog.set_config('modellang.correlation_id', '', true);
  PERFORM pg_catalog.set_config('modellang.causation_id', '', true);

  IF v_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.delegation', pg_catalog.to_jsonb("p_delegation"), 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.environment', pg_catalog.to_jsonb("p_environment"), 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.commitSha', pg_catalog.to_jsonb("p_commit_sha")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_d10d1618ed4045f396b64fc3745ce3dd' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_d10d1618ed4045f396b64fc3745ce3dd';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_d10d1618ed4045f396b64fc3745ce3dd';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."delegation"
  WHERE "id" = ANY (ARRAY["p_delegation"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."environment"
  WHERE "id" = ANY (ARRAY["p_environment"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_delegation
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  SELECT row_value.xmin::text INTO v_delegation_xmin
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT * INTO v_environment
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  SELECT row_value.xmin::text INTO v_environment_xmin
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.commitSha', 'value', pg_catalog.to_jsonb("p_commit_sha"))))::text);

  IF NOT (((((CASE WHEN ((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_PRODUCTION_DEPLOY')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  v_authority_policy_id := 'policy:pol_6bb7a7ee2c0040f0a4ab4197ad4ef05a';
  v_authority_id := CASE WHEN ((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_PRODUCTION_DEPLOY')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id"))) IS TRUE) THEN 'policyBranch:pbr_a1caa050a0174a1d9c9e75137153a4d0' ELSE NULL END;

  IF NOT (((v_environment."tier" = 'PRODUCTION')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_d10d1618ed4045f396b64fc3745ce3dd.production_target';
  END IF;

  INSERT INTO "model_signalbox"."production_deploy_request" ("org_id", "requested_by_id", "environment_id", "commit_sha", "status", "approved_by_id", "approved_by_roles")
  VALUES (v_actor."org_id", v_actor."id", v_environment."id", "p_commit_sha", 'PENDING_APPROVAL', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'environment', v_result."environment_id", 'commitSha', v_result."commit_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_d10d1618ed4045f396b64fc3745ce3dd', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.50.0', 'sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a'), 'actionId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_d10d1618ed4045f396b64fc3745ce3dd.production_target', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_d10d1618ed4045f396b64fc3745ce3dd.0', 0, 'create', 'entity:ent_e2b5ba3cccef437796b2048fd1ff2f24', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."request_production_deployment"(uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."approve_production_deployment"("p_request" uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_identity_issuer text;
  v_identity_subject text;
  v_revision text;
  v_expected_revision text;
  v_idempotency_key text;
  v_correlation_id text;
  v_causation_id text;
  v_request_hash text;
  v_receipt_source_hash text;
  v_receipt_request_hash text;
  v_receipt_status text;
  v_receipt_id bigint;
  v_action_audit_id bigint;
  v_receipt_response jsonb;
  v_response jsonb;
  v_authority_policy_id text;
  v_authority_id text;
  v_result "model_signalbox"."approval"%ROWTYPE;
  v_effect_target_0 uuid;
  v_effect_target_1 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_request_xmin text;
BEGIN
  SELECT identity."principal_id", identity."identity_issuer", identity."identity_subject"
  INTO v_principal_id, v_identity_issuer, v_identity_subject
  FROM "model_signalbox_internal"."resolve_principal"() AS identity;

  v_expected_revision := NULLIF(pg_catalog.current_setting('modellang.expected_revision', true), '');
  v_idempotency_key := NULLIF(pg_catalog.current_setting('modellang.idempotency_key', true), '');
  v_correlation_id := NULLIF(pg_catalog.current_setting('modellang.correlation_id', true), '');
  v_causation_id := NULLIF(pg_catalog.current_setting('modellang.causation_id', true), '');
  PERFORM pg_catalog.set_config('modellang.expected_revision', '', true);
  PERFORM pg_catalog.set_config('modellang.idempotency_key', '', true);
  PERFORM pg_catalog.set_config('modellang.correlation_id', '', true);
  PERFORM pg_catalog.set_config('modellang.causation_id', '', true);

  IF v_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.request', pg_catalog.to_jsonb("p_request")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'action:act_047a601f15384b5ea4bfa05b5ef72676', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_047a601f15384b5ea4bfa05b5ef72676' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_047a601f15384b5ea4bfa05b5ef72676';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_047a601f15384b5ea4bfa05b5ef72676';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."production_deploy_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  v_authority_policy_id := 'policy:pol_08ab785a8747405bbdfeb05009a9df9d';
  v_authority_id := CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 'policyBranch:pbr_3c3833abc88242adb5090ed343f32057' ELSE NULL END;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_047a601f15384b5ea4bfa05b5ef72676.awaiting_approval';
  END IF;

  UPDATE "model_signalbox"."production_deploy_request"
  SET "status" = 'APPROVED',
      "approved_by_id" = v_actor."id",
      "approved_by_roles" = v_actor."roles"
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."approval" ("org_id", "request_id", "approver_id")
  VALUES (v_request."org_id", v_request."id", v_actor."id")
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'decidedAt', v_result."decided_at", 'org', v_result."org_id", 'request', v_result."request_id", 'approver', v_result."approver_id");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_047a601f15384b5ea4bfa05b5ef72676', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.50.0', 'sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a'), 'actionId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_047a601f15384b5ea4bfa05b5ef72676.awaiting_approval', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_047a601f15384b5ea4bfa05b5ef72676.0', 0, 'update', 'entity:ent_e2b5ba3cccef437796b2048fd1ff2f24', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_047a601f15384b5ea4bfa05b5ef72676.1', 1, 'create', 'entity:ent_f6f083c592f34c07af0204bb507be013', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."approve_production_deployment"(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."execute_approved_deployment"("p_request" uuid, "p_allowance" uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_identity_issuer text;
  v_identity_subject text;
  v_revision text;
  v_expected_revision text;
  v_idempotency_key text;
  v_correlation_id text;
  v_causation_id text;
  v_request_hash text;
  v_receipt_source_hash text;
  v_receipt_request_hash text;
  v_receipt_status text;
  v_receipt_id bigint;
  v_action_audit_id bigint;
  v_receipt_response jsonb;
  v_response jsonb;
  v_authority_policy_id text;
  v_authority_id text;
  v_result "model_signalbox"."execution"%ROWTYPE;
  v_effect_target_0 uuid;
  v_effect_target_1 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
BEGIN
  SELECT identity."principal_id", identity."identity_issuer", identity."identity_subject"
  INTO v_principal_id, v_identity_issuer, v_identity_subject
  FROM "model_signalbox_internal"."resolve_principal"() AS identity;

  v_expected_revision := NULLIF(pg_catalog.current_setting('modellang.expected_revision', true), '');
  v_idempotency_key := NULLIF(pg_catalog.current_setting('modellang.idempotency_key', true), '');
  v_correlation_id := NULLIF(pg_catalog.current_setting('modellang.correlation_id', true), '');
  v_causation_id := NULLIF(pg_catalog.current_setting('modellang.causation_id', true), '');
  PERFORM pg_catalog.set_config('modellang.expected_revision', '', true);
  PERFORM pg_catalog.set_config('modellang.idempotency_key', '', true);
  PERFORM pg_catalog.set_config('modellang.correlation_id', '', true);
  PERFORM pg_catalog.set_config('modellang.causation_id', '', true);

  IF v_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.request', pg_catalog.to_jsonb("p_request"), 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance', pg_catalog.to_jsonb("p_allowance")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'action:act_4a9421bfc2e744969b9f73109e6cda54', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_4a9421bfc2e744969b9f73109e6cda54' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_4a9421bfc2e744969b9f73109e6cda54';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_4a9421bfc2e744969b9f73109e6cda54';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."allowance"
  WHERE "id" = ANY (ARRAY["p_allowance"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."production_deploy_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_request
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin))))::text);

  IF NOT ((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('ADMIN' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  IF NOT (((v_request."status" = 'APPROVED')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_4a9421bfc2e744969b9f73109e6cda54.approved';
  END IF;

  IF NOT (((v_allowance."org_id" = v_request."org_id")) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance_same_org';
  END IF;

  UPDATE "model_signalbox"."production_deploy_request"
  SET "status" = 'EXECUTED'
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."execution" ("org_id", "request_id", "allowance_id")
  VALUES (v_request."org_id", v_request."id", v_allowance."id")
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'request', v_result."request_id", 'allowance', v_result."allowance_id");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_4a9421bfc2e744969b9f73109e6cda54', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.50.0', 'sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a'), 'actionId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.approved', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance_same_org', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_4a9421bfc2e744969b9f73109e6cda54.0', 0, 'update', 'entity:ent_e2b5ba3cccef437796b2048fd1ff2f24', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_4a9421bfc2e744969b9f73109e6cda54.1', 1, 'create', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."execute_approved_deployment"(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."reject_production_deployment"("p_request" uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_identity_issuer text;
  v_identity_subject text;
  v_revision text;
  v_expected_revision text;
  v_idempotency_key text;
  v_correlation_id text;
  v_causation_id text;
  v_request_hash text;
  v_receipt_source_hash text;
  v_receipt_request_hash text;
  v_receipt_status text;
  v_receipt_id bigint;
  v_action_audit_id bigint;
  v_receipt_response jsonb;
  v_response jsonb;
  v_authority_policy_id text;
  v_authority_id text;
  v_result "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_request_xmin text;
BEGIN
  SELECT identity."principal_id", identity."identity_issuer", identity."identity_subject"
  INTO v_principal_id, v_identity_issuer, v_identity_subject
  FROM "model_signalbox_internal"."resolve_principal"() AS identity;

  v_expected_revision := NULLIF(pg_catalog.current_setting('modellang.expected_revision', true), '');
  v_idempotency_key := NULLIF(pg_catalog.current_setting('modellang.idempotency_key', true), '');
  v_correlation_id := NULLIF(pg_catalog.current_setting('modellang.correlation_id', true), '');
  v_causation_id := NULLIF(pg_catalog.current_setting('modellang.causation_id', true), '');
  PERFORM pg_catalog.set_config('modellang.expected_revision', '', true);
  PERFORM pg_catalog.set_config('modellang.idempotency_key', '', true);
  PERFORM pg_catalog.set_config('modellang.correlation_id', '', true);
  PERFORM pg_catalog.set_config('modellang.causation_id', '', true);

  IF v_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_18ab026d358144dfa4d1729e40dd832e.request', pg_catalog.to_jsonb("p_request")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'action:act_18ab026d358144dfa4d1729e40dd832e', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_18ab026d358144dfa4d1729e40dd832e' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_18ab026d358144dfa4d1729e40dd832e';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_18ab026d358144dfa4d1729e40dd832e';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."production_deploy_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  v_authority_policy_id := 'policy:pol_08ab785a8747405bbdfeb05009a9df9d';
  v_authority_id := CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 'policyBranch:pbr_3c3833abc88242adb5090ed343f32057' ELSE NULL END;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_18ab026d358144dfa4d1729e40dd832e.awaiting_approval';
  END IF;

  UPDATE "model_signalbox"."production_deploy_request"
  SET "status" = 'REJECTED'
  WHERE "id" = v_request."id"
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'environment', v_result."environment_id", 'commitSha', v_result."commit_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_18ab026d358144dfa4d1729e40dd832e', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.50.0', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.50.0', 'sourceHash', 'sha256:30952e600e16dee04604d4d1c6be9e8712098c8b5fad4cd366f70d52abf8c85a'), 'actionId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_18ab026d358144dfa4d1729e40dd832e.awaiting_approval', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_18ab026d358144dfa4d1729e40dd832e.0', 0, 'update', 'entity:ent_e2b5ba3cccef437796b2048fd1ff2f24', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."reject_production_deployment"(uuid) FROM PUBLIC;

RESET ROLE;
