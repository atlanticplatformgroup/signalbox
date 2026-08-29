-- Generated guarded action functions. Caller identity is resolved from direct login or transaction-bound gateway context.
SET ROLE modellang_owner;

CREATE OR REPLACE FUNCTION "model_signalbox"."request_issue_creation"("p_delegation" uuid, "p_repository" uuid, "p_connector" uuid, "p_title" text, "p_body" text)
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
  v_result "model_signalbox"."issue_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_repository "model_signalbox"."repository"%ROWTYPE;
  v_repository_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_ea693a4d658449fbab5741b8369bc276.delegation', pg_catalog.to_jsonb("p_delegation"), 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.repository', pg_catalog.to_jsonb("p_repository"), 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.connector', pg_catalog.to_jsonb("p_connector"), 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.title', pg_catalog.to_jsonb("p_title"), 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.body', pg_catalog.to_jsonb("p_body")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_ea693a4d658449fbab5741b8369bc276', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_ea693a4d658449fbab5741b8369bc276' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_ea693a4d658449fbab5741b8369bc276';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_ea693a4d658449fbab5741b8369bc276';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."delegation"
  WHERE "id" = ANY (ARRAY["p_delegation"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."repository"
  WHERE "id" = ANY (ARRAY["p_repository"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_delegation
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  SELECT row_value.xmin::text INTO v_delegation_xmin
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT * INTO v_repository
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  SELECT row_value.xmin::text INTO v_repository_xmin
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.repository', 'value', pg_catalog.to_jsonb("p_repository"), 'rowVersion', pg_catalog.to_jsonb(v_repository_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.title', 'value', pg_catalog.to_jsonb("p_title")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.body', 'value', pg_catalog.to_jsonb("p_body"))))::text);

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'CREATE_ISSUE')) AND (v_delegation."repository_id" = (v_repository."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_repository."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_repository."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_ea693a4d658449fbab5741b8369bc276';
  END IF;

  v_authority_policy_id := 'policy:pol_283b5ccf33154f469de3572557c213de';
  v_authority_id := CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'CREATE_ISSUE')) AND (v_delegation."repository_id" = (v_repository."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_repository."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_repository."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 'policyBranch:pbr_ba69b7197f1d46628c1b933973088326' ELSE NULL END;

  INSERT INTO "model_signalbox"."issue_request" ("org_id", "requested_by_id", "delegation_id", "repository_id", "connector_id", "title", "body", "status")
  VALUES (v_actor."org_id", v_actor."id", v_delegation."id", v_repository."id", v_connector."id", "p_title", "p_body", 'READY')
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'repository', v_result."repository_id", 'connector', v_result."connector_id", 'title', v_result."title", 'body', v_result."body", 'status', v_result."status");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_ea693a4d658449fbab5741b8369bc276', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_ea693a4d658449fbab5741b8369bc276', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_ea693a4d658449fbab5741b8369bc276', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array()), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_ea693a4d658449fbab5741b8369bc276.0', 0, 'create', 'entity:ent_d66226c7efc345ba9853df0d4abb879a', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."request_issue_creation"(uuid, uuid, uuid, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."request_pull_request"("p_delegation" uuid, "p_repository" uuid, "p_connector" uuid, "p_head_branch" text, "p_base_branch" text, "p_title" text)
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
  v_result "model_signalbox"."pull_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_repository "model_signalbox"."repository"%ROWTYPE;
  v_repository_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.delegation', pg_catalog.to_jsonb("p_delegation"), 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.repository', pg_catalog.to_jsonb("p_repository"), 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.connector', pg_catalog.to_jsonb("p_connector"), 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.headBranch', pg_catalog.to_jsonb("p_head_branch"), 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.baseBranch', pg_catalog.to_jsonb("p_base_branch"), 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.title', pg_catalog.to_jsonb("p_title")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_c4bb8af190dd48efb9784efb9ff9030c' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_c4bb8af190dd48efb9784efb9ff9030c';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_c4bb8af190dd48efb9784efb9ff9030c';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."delegation"
  WHERE "id" = ANY (ARRAY["p_delegation"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."repository"
  WHERE "id" = ANY (ARRAY["p_repository"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_delegation
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  SELECT row_value.xmin::text INTO v_delegation_xmin
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT * INTO v_repository
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  SELECT row_value.xmin::text INTO v_repository_xmin
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.repository', 'value', pg_catalog.to_jsonb("p_repository"), 'rowVersion', pg_catalog.to_jsonb(v_repository_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.headBranch', 'value', pg_catalog.to_jsonb("p_head_branch")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.baseBranch', 'value', pg_catalog.to_jsonb("p_base_branch")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.title', 'value', pg_catalog.to_jsonb("p_title"))))::text);

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'OPEN_PULL_REQUEST')) AND (v_delegation."repository_id" = (v_repository."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_repository."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_repository."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_c4bb8af190dd48efb9784efb9ff9030c';
  END IF;

  v_authority_policy_id := 'policy:pol_d216aa190a554575a6431304ff70ea3b';
  v_authority_id := CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'OPEN_PULL_REQUEST')) AND (v_delegation."repository_id" = (v_repository."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_repository."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_repository."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 'policyBranch:pbr_f405313968a34706a0b46b81eb41114e' ELSE NULL END;

  INSERT INTO "model_signalbox"."pull_request" ("org_id", "requested_by_id", "delegation_id", "repository_id", "connector_id", "head_branch", "base_branch", "title", "status")
  VALUES (v_actor."org_id", v_actor."id", v_delegation."id", v_repository."id", v_connector."id", "p_head_branch", "p_base_branch", "p_title", 'READY')
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'repository', v_result."repository_id", 'connector', v_result."connector_id", 'headBranch', v_result."head_branch", 'baseBranch', v_result."base_branch", 'title', v_result."title", 'status', v_result."status");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_c4bb8af190dd48efb9784efb9ff9030c', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array()), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_c4bb8af190dd48efb9784efb9ff9030c.0', 0, 'create', 'entity:ent_44eefd913a6d40389e4b1baf02add8c4', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."request_pull_request"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."request_staging_deployment"("p_delegation" uuid, "p_environment" uuid, "p_connector" uuid, "p_commit_sha" text)
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
  v_result "model_signalbox"."deployment_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_environment "model_signalbox"."environment"%ROWTYPE;
  v_environment_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_1388eb9f38684fa0830f60156cdba497.delegation', pg_catalog.to_jsonb("p_delegation"), 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.environment', pg_catalog.to_jsonb("p_environment"), 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.connector', pg_catalog.to_jsonb("p_connector"), 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.commitSha', pg_catalog.to_jsonb("p_commit_sha")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_1388eb9f38684fa0830f60156cdba497', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_1388eb9f38684fa0830f60156cdba497' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_1388eb9f38684fa0830f60156cdba497';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_1388eb9f38684fa0830f60156cdba497';
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

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_delegation
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  SELECT row_value.xmin::text INTO v_delegation_xmin
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT * INTO v_environment
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  SELECT row_value.xmin::text INTO v_environment_xmin
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.commitSha', 'value', pg_catalog.to_jsonb("p_commit_sha"))))::text);

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'DEPLOY_STAGING')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_1388eb9f38684fa0830f60156cdba497';
  END IF;

  v_authority_policy_id := 'policy:pol_8410bf38cec54a4ea73fd2eb23b0559c';
  v_authority_id := CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'DEPLOY_STAGING')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 'policyBranch:pbr_ab4c955d5582438e87f04e1d4984b535' ELSE NULL END;

  IF NOT (((v_environment."tier" = 'STAGING')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_1388eb9f38684fa0830f60156cdba497.staging_target';
  END IF;

  INSERT INTO "model_signalbox"."deployment_request" ("org_id", "requested_by_id", "delegation_id", "environment_id", "environment_tier", "connector_id", "commit_sha", "status", "approved_by_id", "approved_by_roles")
  VALUES (v_actor."org_id", v_actor."id", v_delegation."id", v_environment."id", v_environment."tier", v_connector."id", "p_commit_sha", 'READY', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'environment', v_result."environment_id", 'environmentTier', v_result."environment_tier", 'connector', v_result."connector_id", 'commitSha', v_result."commit_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_1388eb9f38684fa0830f60156cdba497', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_1388eb9f38684fa0830f60156cdba497', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_1388eb9f38684fa0830f60156cdba497', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_1388eb9f38684fa0830f60156cdba497.staging_target', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_1388eb9f38684fa0830f60156cdba497.0', 0, 'create', 'entity:ent_e2b5ba3cccef437796b2048fd1ff2f24', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."request_staging_deployment"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."request_production_deployment"("p_delegation" uuid, "p_environment" uuid, "p_connector" uuid, "p_commit_sha" text)
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
  v_result "model_signalbox"."deployment_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_environment "model_signalbox"."environment"%ROWTYPE;
  v_environment_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.delegation', pg_catalog.to_jsonb("p_delegation"), 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.environment', pg_catalog.to_jsonb("p_environment"), 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.connector', pg_catalog.to_jsonb("p_connector"), 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.commitSha', pg_catalog.to_jsonb("p_commit_sha")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_d10d1618ed4045f396b64fc3745ce3dd' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
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

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.commitSha', 'value', pg_catalog.to_jsonb("p_commit_sha"))))::text);

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_PRODUCTION_DEPLOY')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_d10d1618ed4045f396b64fc3745ce3dd';
  END IF;

  v_authority_policy_id := 'policy:pol_6bb7a7ee2c0040f0a4ab4197ad4ef05a';
  v_authority_id := CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_PRODUCTION_DEPLOY')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 'policyBranch:pbr_a1caa050a0174a1d9c9e75137153a4d0' ELSE NULL END;

  IF NOT (((v_environment."tier" = 'PRODUCTION')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_d10d1618ed4045f396b64fc3745ce3dd.production_target';
  END IF;

  INSERT INTO "model_signalbox"."deployment_request" ("org_id", "requested_by_id", "delegation_id", "environment_id", "environment_tier", "connector_id", "commit_sha", "status", "approved_by_id", "approved_by_roles")
  VALUES (v_actor."org_id", v_actor."id", v_delegation."id", v_environment."id", v_environment."tier", v_connector."id", "p_commit_sha", 'PENDING_APPROVAL', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'environment', v_result."environment_id", 'environmentTier', v_result."environment_tier", 'connector', v_result."connector_id", 'commitSha', v_result."commit_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_d10d1618ed4045f396b64fc3745ce3dd', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_d10d1618ed4045f396b64fc3745ce3dd.production_target', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
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

REVOKE ALL ON FUNCTION "model_signalbox"."request_production_deployment"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."request_schema_migration"("p_delegation" uuid, "p_environment" uuid, "p_connector" uuid, "p_migration_name" text, "p_migration_sha" text)
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
  v_result "model_signalbox"."schema_migration_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_environment "model_signalbox"."environment"%ROWTYPE;
  v_environment_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_411bfff32560406186bd2d442f1ecf3b.delegation', pg_catalog.to_jsonb("p_delegation"), 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.environment', pg_catalog.to_jsonb("p_environment"), 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.connector', pg_catalog.to_jsonb("p_connector"), 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.migrationName', pg_catalog.to_jsonb("p_migration_name"), 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.migrationSha', pg_catalog.to_jsonb("p_migration_sha")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_411bfff32560406186bd2d442f1ecf3b', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_411bfff32560406186bd2d442f1ecf3b' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_411bfff32560406186bd2d442f1ecf3b';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_411bfff32560406186bd2d442f1ecf3b';
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

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_delegation
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  SELECT row_value.xmin::text INTO v_delegation_xmin
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT * INTO v_environment
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  SELECT row_value.xmin::text INTO v_environment_xmin
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.migrationName', 'value', pg_catalog.to_jsonb("p_migration_name")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.migrationSha', 'value', pg_catalog.to_jsonb("p_migration_sha"))))::text);

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_SCHEMA_MIGRATION')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_411bfff32560406186bd2d442f1ecf3b';
  END IF;

  v_authority_policy_id := 'policy:pol_6c92cfdbe32b49b19614dbe9ef2af933';
  v_authority_id := CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_SCHEMA_MIGRATION')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 'policyBranch:pbr_412a7007281b46bbb7a2831262299e91' ELSE NULL END;

  INSERT INTO "model_signalbox"."schema_migration_request" ("org_id", "requested_by_id", "delegation_id", "environment_id", "connector_id", "migration_name", "migration_sha", "status", "approved_by_id", "approved_by_roles")
  VALUES (v_actor."org_id", v_actor."id", v_delegation."id", v_environment."id", v_connector."id", "p_migration_name", "p_migration_sha", 'PENDING_APPROVAL', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'environment', v_result."environment_id", 'connector', v_result."connector_id", 'migrationName', v_result."migration_name", 'migrationSha', v_result."migration_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_411bfff32560406186bd2d442f1ecf3b', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_411bfff32560406186bd2d442f1ecf3b', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_411bfff32560406186bd2d442f1ecf3b', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array()), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_411bfff32560406186bd2d442f1ecf3b.0', 0, 'create', 'entity:ent_c136762ce9794a7b92ca3c138c7c7bef', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."request_schema_migration"(uuid, uuid, uuid, text, text) FROM PUBLIC;

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
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
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
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_047a601f15384b5ea4bfa05b5ef72676', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_047a601f15384b5ea4bfa05b5ef72676' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
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

  PERFORM "id" FROM "model_signalbox"."deployment_request"
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
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_047a601f15384b5ea4bfa05b5ef72676';
  END IF;

  v_authority_policy_id := 'policy:pol_08ab785a8747405bbdfeb05009a9df9d';
  v_authority_id := CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 'policyBranch:pbr_3c3833abc88242adb5090ed343f32057' ELSE NULL END;

  IF NOT (((v_request."environment_tier" = 'PRODUCTION')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_047a601f15384b5ea4bfa05b5ef72676.production_request';
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_047a601f15384b5ea4bfa05b5ef72676.awaiting_approval';
  END IF;

  UPDATE "model_signalbox"."deployment_request"
  SET "status" = 'APPROVED',
      "approved_by_id" = v_actor."id",
      "approved_by_roles" = v_actor."roles"
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."approval" ("org_id", "request_id", "request_kind", "requested_by_id", "approver_id", "approver_roles")
  VALUES (v_request."org_id", v_request."id", 'DEPLOYMENT', v_request."requested_by_id", v_actor."id", v_actor."roles")
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'decidedAt', v_result."decided_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'approver', v_result."approver_id", 'approverRoles', v_result."approver_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_047a601f15384b5ea4bfa05b5ef72676', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_047a601f15384b5ea4bfa05b5ef72676.production_request', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_047a601f15384b5ea4bfa05b5ef72676.awaiting_approval', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
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
  v_result "model_signalbox"."deployment_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
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
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_18ab026d358144dfa4d1729e40dd832e', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_18ab026d358144dfa4d1729e40dd832e' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
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

  PERFORM "id" FROM "model_signalbox"."deployment_request"
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
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_18ab026d358144dfa4d1729e40dd832e';
  END IF;

  v_authority_policy_id := 'policy:pol_08ab785a8747405bbdfeb05009a9df9d';
  v_authority_id := CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 'policyBranch:pbr_3c3833abc88242adb5090ed343f32057' ELSE NULL END;

  IF NOT (((v_request."environment_tier" = 'PRODUCTION')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_18ab026d358144dfa4d1729e40dd832e.production_request';
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_18ab026d358144dfa4d1729e40dd832e.awaiting_approval';
  END IF;

  UPDATE "model_signalbox"."deployment_request"
  SET "status" = 'REJECTED'
  WHERE "id" = v_request."id"
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'environment', v_result."environment_id", 'environmentTier', v_result."environment_tier", 'connector', v_result."connector_id", 'commitSha', v_result."commit_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_18ab026d358144dfa4d1729e40dd832e', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_18ab026d358144dfa4d1729e40dd832e.production_request', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_18ab026d358144dfa4d1729e40dd832e.awaiting_approval', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
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

CREATE OR REPLACE FUNCTION "model_signalbox"."approve_schema_migration"("p_request" uuid)
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
  v_request "model_signalbox"."schema_migration_request"%ROWTYPE;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.request', pg_catalog.to_jsonb("p_request")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."schema_migration_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d';
  END IF;

  v_authority_policy_id := 'policy:pol_ee8441bff1214fbab3a420e3f02e899c';
  v_authority_id := CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 'policyBranch:pbr_099459e0688e4de4b44b6410cbfbe3a3' ELSE NULL END;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.awaiting_approval';
  END IF;

  UPDATE "model_signalbox"."schema_migration_request"
  SET "status" = 'APPROVED',
      "approved_by_id" = v_actor."id",
      "approved_by_roles" = v_actor."roles"
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."approval" ("org_id", "request_id", "request_kind", "requested_by_id", "approver_id", "approver_roles")
  VALUES (v_request."org_id", v_request."id", 'SCHEMA_MIGRATION', v_request."requested_by_id", v_actor."id", v_actor."roles")
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'decidedAt', v_result."decided_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'approver', v_result."approver_id", 'approverRoles', v_result."approver_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.awaiting_approval', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.0', 0, 'update', 'entity:ent_c136762ce9794a7b92ca3c138c7c7bef', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.1', 1, 'create', 'entity:ent_f6f083c592f34c07af0204bb507be013', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."approve_schema_migration"(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."reject_schema_migration"("p_request" uuid)
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
  v_result "model_signalbox"."schema_migration_request"%ROWTYPE;
  v_effect_target_0 uuid;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."schema_migration_request"%ROWTYPE;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_d3a1935e42f24e4d84d25bc05ee690ad.request', pg_catalog.to_jsonb("p_request")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_d3a1935e42f24e4d84d25bc05ee690ad' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."schema_migration_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d3a1935e42f24e4d84d25bc05ee690ad.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d3a1935e42f24e4d84d25bc05ee690ad.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_d3a1935e42f24e4d84d25bc05ee690ad';
  END IF;

  v_authority_policy_id := 'policy:pol_ee8441bff1214fbab3a420e3f02e899c';
  v_authority_id := CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 'policyBranch:pbr_099459e0688e4de4b44b6410cbfbe3a3' ELSE NULL END;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_d3a1935e42f24e4d84d25bc05ee690ad.awaiting_approval';
  END IF;

  UPDATE "model_signalbox"."schema_migration_request"
  SET "status" = 'REJECTED'
  WHERE "id" = v_request."id"
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'createdAt', v_result."created_at", 'org', v_result."org_id", 'requestedBy', v_result."requested_by_id", 'delegation', v_result."delegation_id", 'environment', v_result."environment_id", 'connector', v_result."connector_id", 'migrationName', v_result."migration_name", 'migrationSha', v_result."migration_sha", 'status', v_result."status", 'approvedBy', v_result."approved_by_id", 'approvedByRoles', v_result."approved_by_roles");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_d3a1935e42f24e4d84d25bc05ee690ad', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_d3a1935e42f24e4d84d25bc05ee690ad.awaiting_approval', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_d3a1935e42f24e4d84d25bc05ee690ad.0', 0, 'update', 'entity:ent_c136762ce9794a7b92ca3c138c7c7bef', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."reject_schema_migration"(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."dispatch_issue_creation"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid)
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
  v_request "model_signalbox"."issue_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.request', pg_catalog.to_jsonb("p_request"), 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.allowance', pg_catalog.to_jsonb("p_allowance"), 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.connector', pg_catalog.to_jsonb("p_connector")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_cbb72fd307704ab3927aa4bea8112fbf' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_cbb72fd307704ab3927aa4bea8112fbf';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_cbb72fd307704ab3927aa4bea8112fbf';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."allowance"
  WHERE "id" = ANY (ARRAY["p_allowance"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."issue_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_request
  FROM "model_signalbox"."issue_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."issue_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_cbb72fd307704ab3927aa4bea8112fbf';
  END IF;

  IF NOT (((v_request."status" = 'READY')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_cbb72fd307704ab3927aa4bea8112fbf.ready';
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_cbb72fd307704ab3927aa4bea8112fbf.allowance_scope';
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_cbb72fd307704ab3927aa4bea8112fbf.connector_active';
  END IF;

  UPDATE "model_signalbox"."issue_request"
  SET "status" = 'DISPATCHED'
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."execution" ("org_id", "request_id", "request_kind", "requested_by_id", "connector_id", "allowance_id", "status", "external_reference", "failure_message")
  VALUES (v_request."org_id", v_request."id", 'ISSUE', v_request."requested_by_id", v_connector."id", v_allowance."id", 'PENDING', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_cbb72fd307704ab3927aa4bea8112fbf', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_cbb72fd307704ab3927aa4bea8112fbf.ready', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_cbb72fd307704ab3927aa4bea8112fbf.allowance_scope', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_cbb72fd307704ab3927aa4bea8112fbf.connector_active', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_cbb72fd307704ab3927aa4bea8112fbf.0', 0, 'update', 'entity:ent_d66226c7efc345ba9853df0d4abb879a', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_cbb72fd307704ab3927aa4bea8112fbf.1', 1, 'create', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_issue_creation"(uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."dispatch_pull_request"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid)
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
  v_request "model_signalbox"."pull_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_3e99da927be642efac3d1bee026ef00a.request', pg_catalog.to_jsonb("p_request"), 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.allowance', pg_catalog.to_jsonb("p_allowance"), 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.connector', pg_catalog.to_jsonb("p_connector")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_3e99da927be642efac3d1bee026ef00a', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_3e99da927be642efac3d1bee026ef00a' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_3e99da927be642efac3d1bee026ef00a';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_3e99da927be642efac3d1bee026ef00a';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."pull_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  PERFORM "id" FROM "model_signalbox"."allowance"
  WHERE "id" = ANY (ARRAY["p_allowance"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."pull_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."pull_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_3e99da927be642efac3d1bee026ef00a';
  END IF;

  IF NOT (((v_request."status" = 'READY')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_3e99da927be642efac3d1bee026ef00a.ready';
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_3e99da927be642efac3d1bee026ef00a.allowance_scope';
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_3e99da927be642efac3d1bee026ef00a.connector_active';
  END IF;

  UPDATE "model_signalbox"."pull_request"
  SET "status" = 'DISPATCHED'
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."execution" ("org_id", "request_id", "request_kind", "requested_by_id", "connector_id", "allowance_id", "status", "external_reference", "failure_message")
  VALUES (v_request."org_id", v_request."id", 'PULL_REQUEST', v_request."requested_by_id", v_connector."id", v_allowance."id", 'PENDING', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_3e99da927be642efac3d1bee026ef00a', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_3e99da927be642efac3d1bee026ef00a', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_3e99da927be642efac3d1bee026ef00a', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_3e99da927be642efac3d1bee026ef00a.ready', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_3e99da927be642efac3d1bee026ef00a.allowance_scope', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_3e99da927be642efac3d1bee026ef00a.connector_active', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_3e99da927be642efac3d1bee026ef00a.0', 0, 'update', 'entity:ent_44eefd913a6d40389e4b1baf02add8c4', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_3e99da927be642efac3d1bee026ef00a.1', 1, 'create', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_pull_request"(uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."dispatch_staging_deployment"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid)
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
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_3e26a4d454634bf3a2058204146d7c45.request', pg_catalog.to_jsonb("p_request"), 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.allowance', pg_catalog.to_jsonb("p_allowance"), 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.connector', pg_catalog.to_jsonb("p_connector")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_3e26a4d454634bf3a2058204146d7c45', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_3e26a4d454634bf3a2058204146d7c45' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_3e26a4d454634bf3a2058204146d7c45';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_3e26a4d454634bf3a2058204146d7c45';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."allowance"
  WHERE "id" = ANY (ARRAY["p_allowance"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."deployment_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT * INTO v_request
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_3e26a4d454634bf3a2058204146d7c45';
  END IF;

  IF NOT ((((v_request."environment_tier" = 'STAGING') AND (v_request."status" = 'READY'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_3e26a4d454634bf3a2058204146d7c45.staging_request';
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_3e26a4d454634bf3a2058204146d7c45.allowance_scope';
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_3e26a4d454634bf3a2058204146d7c45.connector_active';
  END IF;

  UPDATE "model_signalbox"."deployment_request"
  SET "status" = 'DISPATCHED'
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."execution" ("org_id", "request_id", "request_kind", "requested_by_id", "connector_id", "allowance_id", "status", "external_reference", "failure_message")
  VALUES (v_request."org_id", v_request."id", 'DEPLOYMENT', v_request."requested_by_id", v_connector."id", v_allowance."id", 'PENDING', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_3e26a4d454634bf3a2058204146d7c45', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_3e26a4d454634bf3a2058204146d7c45', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_3e26a4d454634bf3a2058204146d7c45', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_3e26a4d454634bf3a2058204146d7c45.staging_request', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_3e26a4d454634bf3a2058204146d7c45.allowance_scope', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_3e26a4d454634bf3a2058204146d7c45.connector_active', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_3e26a4d454634bf3a2058204146d7c45.0', 0, 'update', 'entity:ent_e2b5ba3cccef437796b2048fd1ff2f24', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_3e26a4d454634bf3a2058204146d7c45.1', 1, 'create', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_staging_deployment"(uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."dispatch_approved_deployment"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid)
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
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.request', pg_catalog.to_jsonb("p_request"), 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance', pg_catalog.to_jsonb("p_allowance"), 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.connector', pg_catalog.to_jsonb("p_connector")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_4a9421bfc2e744969b9f73109e6cda54', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_4a9421bfc2e744969b9f73109e6cda54' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
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

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."deployment_request"
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT * INTO v_request
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_4a9421bfc2e744969b9f73109e6cda54';
  END IF;

  IF NOT ((((v_request."environment_tier" = 'PRODUCTION') AND (v_request."status" = 'APPROVED'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_4a9421bfc2e744969b9f73109e6cda54.approved_production_request';
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance_scope';
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_4a9421bfc2e744969b9f73109e6cda54.connector_active';
  END IF;

  UPDATE "model_signalbox"."deployment_request"
  SET "status" = 'DISPATCHED'
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."execution" ("org_id", "request_id", "request_kind", "requested_by_id", "connector_id", "allowance_id", "status", "external_reference", "failure_message")
  VALUES (v_request."org_id", v_request."id", 'DEPLOYMENT', v_request."requested_by_id", v_connector."id", v_allowance."id", 'PENDING', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_4a9421bfc2e744969b9f73109e6cda54', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.approved_production_request', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance_scope', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.connector_active', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
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

REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_approved_deployment"(uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."dispatch_approved_schema_migration"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid)
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
  v_request "model_signalbox"."schema_migration_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_70d3862584094631aca61e9db664d991';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_70d3862584094631aca61e9db664d991', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_70d3862584094631aca61e9db664d991.request', pg_catalog.to_jsonb("p_request"), 'parameter:action:act_70d3862584094631aca61e9db664d991.allowance', pg_catalog.to_jsonb("p_allowance"), 'parameter:action:act_70d3862584094631aca61e9db664d991.connector', pg_catalog.to_jsonb("p_connector")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_70d3862584094631aca61e9db664d991', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_70d3862584094631aca61e9db664d991' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_70d3862584094631aca61e9db664d991';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_70d3862584094631aca61e9db664d991';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."allowance"
  WHERE "id" = ANY (ARRAY["p_allowance"]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."schema_migration_request"
  WHERE "id" = ANY (ARRAY["p_request"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  PERFORM "id" FROM "model_signalbox"."connector"
  WHERE "id" = ANY (ARRAY["p_connector"]::uuid[])
  ORDER BY "id" FOR SHARE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_request
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_70d3862584094631aca61e9db664d991', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_70d3862584094631aca61e9db664d991';
  END IF;

  IF NOT (((v_request."status" = 'APPROVED')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_70d3862584094631aca61e9db664d991.approved';
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_70d3862584094631aca61e9db664d991.allowance_scope';
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_70d3862584094631aca61e9db664d991.connector_active';
  END IF;

  UPDATE "model_signalbox"."schema_migration_request"
  SET "status" = 'DISPATCHED'
  WHERE "id" = v_request."id"
  RETURNING "id" INTO v_effect_target_0;

  INSERT INTO "model_signalbox"."execution" ("org_id", "request_id", "request_kind", "requested_by_id", "connector_id", "allowance_id", "status", "external_reference", "failure_message")
  VALUES (v_request."org_id", v_request."id", 'SCHEMA_MIGRATION', v_request."requested_by_id", v_connector."id", v_allowance."id", 'PENDING', NULL, NULL)
  RETURNING * INTO v_result;
  v_effect_target_1 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_70d3862584094631aca61e9db664d991', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_70d3862584094631aca61e9db664d991', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_70d3862584094631aca61e9db664d991', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_70d3862584094631aca61e9db664d991', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_70d3862584094631aca61e9db664d991.approved', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_70d3862584094631aca61e9db664d991.allowance_scope', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()), pg_catalog.jsonb_build_object('ruleId', 'require:action:act_70d3862584094631aca61e9db664d991.connector_active', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_70d3862584094631aca61e9db664d991.0', 0, 'update', 'entity:ent_c136762ce9794a7b92ca3c138c7c7bef', v_effect_target_0);

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_70d3862584094631aca61e9db664d991.1', 1, 'create', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_1);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_approved_schema_migration"(uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."complete_execution"("p_execution" uuid, "p_external_reference" text)
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
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_execution "model_signalbox"."execution"%ROWTYPE;
  v_execution_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_5be24324b68d4c2eb334732b36e1b16c';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_5be24324b68d4c2eb334732b36e1b16c';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.execution', pg_catalog.to_jsonb("p_execution"), 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.externalReference', pg_catalog.to_jsonb("p_external_reference")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_5be24324b68d4c2eb334732b36e1b16c', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_5be24324b68d4c2eb334732b36e1b16c' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_5be24324b68d4c2eb334732b36e1b16c';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_5be24324b68d4c2eb334732b36e1b16c';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."execution"
  WHERE "id" = ANY (ARRAY["p_execution"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_5be24324b68d4c2eb334732b36e1b16c';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_execution
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_5be24324b68d4c2eb334732b36e1b16c';
  END IF;

  SELECT row_value.xmin::text INTO v_execution_xmin
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.execution', 'value', pg_catalog.to_jsonb("p_execution"), 'rowVersion', pg_catalog.to_jsonb(v_execution_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.externalReference', 'value', pg_catalog.to_jsonb("p_external_reference"))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_execution."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_5be24324b68d4c2eb334732b36e1b16c';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_5be24324b68d4c2eb334732b36e1b16c';
  END IF;

  IF NOT (((v_execution."status" = 'PENDING')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_5be24324b68d4c2eb334732b36e1b16c.pending';
  END IF;

  UPDATE "model_signalbox"."execution"
  SET "status" = 'SUCCEEDED',
      "external_reference" = "p_external_reference",
      "failure_message" = NULL
  WHERE "id" = v_execution."id"
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_5be24324b68d4c2eb334732b36e1b16c', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_5be24324b68d4c2eb334732b36e1b16c', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_5be24324b68d4c2eb334732b36e1b16c', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_5be24324b68d4c2eb334732b36e1b16c.pending', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_5be24324b68d4c2eb334732b36e1b16c.0', 0, 'update', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."complete_execution"(uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."fail_execution"("p_execution" uuid, "p_failure_message" text)
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
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_execution "model_signalbox"."execution"%ROWTYPE;
  v_execution_xmin text;
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_IDEMPOTENCY_REQUIRED:idempotency:action:act_926686163a6544e79d44dea9336d2c88';
  END IF;
  v_correlation_id := COALESCE(v_correlation_id, v_idempotency_key);

  IF v_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     OR (v_causation_id IS NOT NULL AND v_causation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$')
     OR v_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:idempotency:action:act_926686163a6544e79d44dea9336d2c88';
  END IF;

  v_request_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('actionId', 'action:act_926686163a6544e79d44dea9336d2c88', 'inputs', pg_catalog.jsonb_build_object('parameter:action:act_926686163a6544e79d44dea9336d2c88.execution', pg_catalog.to_jsonb("p_execution"), 'parameter:action:act_926686163a6544e79d44dea9336d2c88.failureMessage', pg_catalog.to_jsonb("p_failure_message")), 'expectedRevision', v_expected_revision, 'correlationId', v_correlation_id, 'causationId', v_causation_id))::text, 'UTF8')), 'hex');
  INSERT INTO "model_signalbox_internal"."command_receipt" ("model_id", "model_version", "source_hash", "action_id", "principal_id", "idempotency_key", "request_hash", "correlation_id", "causation_id")
  VALUES ('model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'action:act_926686163a6544e79d44dea9336d2c88', v_principal_id, v_idempotency_key, v_request_hash, v_correlation_id, v_causation_id)
  ON CONFLICT ("principal_id", "action_id", "idempotency_key") DO NOTHING
  RETURNING "id" INTO v_receipt_id;

  IF v_receipt_id IS NULL THEN
    SELECT "id", "source_hash", "request_hash", "status", "response"
    INTO v_receipt_id, v_receipt_source_hash, v_receipt_request_hash, v_receipt_status, v_receipt_response
    FROM "model_signalbox_internal"."command_receipt"
    WHERE "principal_id" = v_principal_id AND "action_id" = 'action:act_926686163a6544e79d44dea9336d2c88' AND "idempotency_key" = v_idempotency_key;
    IF v_receipt_source_hash IS DISTINCT FROM 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9' OR v_receipt_request_hash IS DISTINCT FROM v_request_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_IDEMPOTENCY_CONFLICT:idempotency:action:act_926686163a6544e79d44dea9336d2c88';
    END IF;
    IF v_receipt_status IS DISTINCT FROM 'executed' OR v_receipt_response IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'ML_IDEMPOTENCY_INCOMPLETE:idempotency:action:act_926686163a6544e79d44dea9336d2c88';
    END IF;
    RETURN v_receipt_response;
  END IF;

  PERFORM "id" FROM "model_signalbox"."principal"
  WHERE "id" = ANY (ARRAY[v_principal_id]::uuid[])
  ORDER BY "id" FOR SHARE;

  PERFORM "id" FROM "model_signalbox"."execution"
  WHERE "id" = ANY (ARRAY["p_execution"]::uuid[])
  ORDER BY "id" FOR UPDATE;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_926686163a6544e79d44dea9336d2c88';
  END IF;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_execution
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution"
;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_926686163a6544e79d44dea9336d2c88';
  END IF;

  SELECT row_value.xmin::text INTO v_execution_xmin
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_926686163a6544e79d44dea9336d2c88.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_926686163a6544e79d44dea9336d2c88.execution', 'value', pg_catalog.to_jsonb("p_execution"), 'rowVersion', pg_catalog.to_jsonb(v_execution_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_926686163a6544e79d44dea9336d2c88.failureMessage', 'value', pg_catalog.to_jsonb("p_failure_message"))))::text);

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_execution."org_id"))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:action:act_926686163a6544e79d44dea9336d2c88';
  END IF;

  IF v_expected_revision IS NOT NULL AND v_expected_revision IS DISTINCT FROM v_revision THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:revision:action:act_926686163a6544e79d44dea9336d2c88';
  END IF;

  IF NOT (((v_execution."status" = 'PENDING')) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ML_PRECONDITION:require:action:act_926686163a6544e79d44dea9336d2c88.pending';
  END IF;

  UPDATE "model_signalbox"."execution"
  SET "status" = 'FAILED',
      "external_reference" = NULL,
      "failure_message" = "p_failure_message"
  WHERE "id" = v_execution."id"
  RETURNING * INTO v_result;
  v_effect_target_0 := v_result."id";

  v_response := jsonb_build_object('id', v_result."id", 'startedAt', v_result."started_at", 'org', v_result."org_id", 'requestId', v_result."request_id", 'requestKind', v_result."request_kind", 'requestedBy', v_result."requested_by_id", 'connector', v_result."connector_id", 'allowance', v_result."allowance_id", 'status', v_result."status", 'externalReference', v_result."external_reference", 'failureMessage', v_result."failure_message");
  INSERT INTO "model_signalbox_internal"."action_audit" ("action_id", "database_principal", "principal_id", "target_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "authorization_rule_id", "decision_outcome", "policy_id", "authority_id", "decision_evidence", "correlation_id", "causation_id", "command_receipt_id")
  VALUES ('action:act_926686163a6544e79d44dea9336d2c88', session_user, v_principal_id, v_result."id", v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.52.0', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'authorize:action:act_926686163a6544e79d44dea9336d2c88', 'executed', v_authority_policy_id, v_authority_id, pg_catalog.jsonb_build_object('version', 2, 'outcome', 'executed', 'model', pg_catalog.jsonb_build_object('id', 'model:Signalbox', 'version', '0.52.0', 'sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9'), 'actionId', 'action:act_926686163a6544e79d44dea9336d2c88', 'command', pg_catalog.jsonb_build_object('correlationId', v_correlation_id, 'causationId', v_causation_id, 'receiptId', v_receipt_id), 'authorization', pg_catalog.jsonb_build_object('ruleId', 'authorize:action:act_926686163a6544e79d44dea9336d2c88', 'outcome', 'passed', 'policyId', v_authority_policy_id, 'authorityId', v_authority_id), 'requirements', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('ruleId', 'require:action:act_926686163a6544e79d44dea9336d2c88.pending', 'outcome', 'passed', 'policyIds', pg_catalog.jsonb_build_array()))), v_correlation_id, v_causation_id, v_receipt_id)
  RETURNING "id" INTO v_action_audit_id;

  INSERT INTO "model_signalbox_internal"."action_effect_audit" ("action_audit_id", "effect_id", "effect_ordinal", "effect_kind", "entity_id", "target_id")
  VALUES (v_action_audit_id, 'effect:action:act_926686163a6544e79d44dea9336d2c88.0', 0, 'update', 'entity:ent_695aab5599c84a78ac8f2ea75ccbdf1d', v_effect_target_0);

  UPDATE "model_signalbox_internal"."command_receipt"
  SET "status" = 'executed', "response" = v_response, "target_id" = v_result."id",
      "action_audit_id" = v_action_audit_id, "completed_at" = pg_catalog.transaction_timestamp()
  WHERE "id" = v_receipt_id;

  RETURN v_response;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."fail_execution"(uuid, text) FROM PUBLIC;

RESET ROLE;
