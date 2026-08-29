-- Generated pure applicability queries. These decisions grant no execution authority.
SET ROLE modellang_owner;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_d10d1618ed4045f396b64fc3745ce3dd"("p_delegation" uuid, "p_environment" uuid, "p_commit_sha" text, p_expected_revision text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_revision text;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_delegation "model_signalbox"."delegation"%ROWTYPE;
  v_delegation_xmin text;
  v_environment "model_signalbox"."environment"%ROWTYPE;
  v_environment_xmin text;
BEGIN
  SELECT identity."principal_id" INTO v_principal_id
  FROM "model_signalbox_internal"."resolve_principal_snapshot"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_delegation
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT row_value.xmin::text INTO v_delegation_xmin
  FROM "model_signalbox"."delegation" AS row_value
  WHERE row_value."id" = "p_delegation";

  SELECT * INTO v_environment
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment";

  SELECT row_value.xmin::text INTO v_environment_xmin
  FROM "model_signalbox"."environment" AS row_value
  WHERE row_value."id" = "p_environment";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.commitSha', 'value', pg_catalog.to_jsonb("p_commit_sha"))))::text);

  IF v_actor_xmin IS NULL OR v_delegation_xmin IS NULL OR v_environment_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd'));
  END IF;

  IF NOT (((((CASE WHEN ((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_PRODUCTION_DEPLOY')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_d10d1618ed4045f396b64fc3745ce3dd'));
  END IF;

  IF NOT (((v_environment."tier" = 'PRODUCTION')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_d10d1618ed4045f396b64fc3745ce3dd.production_target'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_d10d1618ed4045f396b64fc3745ce3dd"(uuid, uuid, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_047a601f15384b5ea4bfa05b5ef72676"("p_request" uuid, p_expected_revision text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_revision text;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_request_xmin text;
BEGIN
  SELECT identity."principal_id" INTO v_principal_id
  FROM "model_signalbox_internal"."resolve_principal_snapshot"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676'));
  END IF;

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_047a601f15384b5ea4bfa05b5ef72676'));
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_047a601f15384b5ea4bfa05b5ef72676.awaiting_approval'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_047a601f15384b5ea4bfa05b5ef72676"(uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_4a9421bfc2e744969b9f73109e6cda54"("p_request" uuid, "p_allowance" uuid, p_expected_revision text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_revision text;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_request "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_request_xmin text;
BEGIN
  SELECT identity."principal_id" INTO v_principal_id
  FROM "model_signalbox_internal"."resolve_principal_snapshot"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_request
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_allowance_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('ADMIN' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_4a9421bfc2e744969b9f73109e6cda54'));
  END IF;

  IF NOT (((v_request."status" = 'APPROVED')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.approved'));
  END IF;

  IF NOT (((v_allowance."org_id" = v_request."org_id")) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance_same_org'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_4a9421bfc2e744969b9f73109e6cda54"(uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_18ab026d358144dfa4d1729e40dd832e"("p_request" uuid, p_expected_revision text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_revision text;
  v_actor "model_signalbox"."principal"%ROWTYPE;
  v_actor_xmin text;
  v_request "model_signalbox"."production_deploy_request"%ROWTYPE;
  v_request_xmin text;
BEGIN
  SELECT identity."principal_id" INTO v_principal_id
  FROM "model_signalbox_internal"."resolve_principal_snapshot"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_request
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."production_deploy_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e'));
  END IF;

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_18ab026d358144dfa4d1729e40dd832e'));
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_18ab026d358144dfa4d1729e40dd832e.awaiting_approval'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_18ab026d358144dfa4d1729e40dd832e"(uuid, text) FROM PUBLIC;

RESET ROLE;
