-- Generated pure applicability queries. These decisions grant no execution authority.
SET ROLE modellang_owner;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_ea693a4d658449fbab5741b8369bc276"("p_delegation" uuid, "p_repository" uuid, "p_connector" uuid, "p_title" text, "p_body" text, p_expected_revision text)
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
  v_repository "model_signalbox"."repository"%ROWTYPE;
  v_repository_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  SELECT * INTO v_repository
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository";

  SELECT row_value.xmin::text INTO v_repository_xmin
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.repository', 'value', pg_catalog.to_jsonb("p_repository"), 'rowVersion', pg_catalog.to_jsonb(v_repository_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.title', 'value', pg_catalog.to_jsonb("p_title")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_ea693a4d658449fbab5741b8369bc276.body', 'value', pg_catalog.to_jsonb("p_body"))))::text);

  IF v_actor_xmin IS NULL OR v_delegation_xmin IS NULL OR v_repository_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_ea693a4d658449fbab5741b8369bc276'));
  END IF;

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'CREATE_ISSUE')) AND (v_delegation."repository_id" = (v_repository."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_repository."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_repository."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_ea693a4d658449fbab5741b8369bc276'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_ea693a4d658449fbab5741b8369bc276'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_ea693a4d658449fbab5741b8369bc276', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_ea693a4d658449fbab5741b8369bc276"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_c4bb8af190dd48efb9784efb9ff9030c"("p_delegation" uuid, "p_repository" uuid, "p_connector" uuid, "p_head_branch" text, "p_base_branch" text, "p_title" text, p_expected_revision text)
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
  v_repository "model_signalbox"."repository"%ROWTYPE;
  v_repository_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  SELECT * INTO v_repository
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository";

  SELECT row_value.xmin::text INTO v_repository_xmin
  FROM "model_signalbox"."repository" AS row_value
  WHERE row_value."id" = "p_repository";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.repository', 'value', pg_catalog.to_jsonb("p_repository"), 'rowVersion', pg_catalog.to_jsonb(v_repository_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.headBranch', 'value', pg_catalog.to_jsonb("p_head_branch")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.baseBranch', 'value', pg_catalog.to_jsonb("p_base_branch")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_c4bb8af190dd48efb9784efb9ff9030c.title', 'value', pg_catalog.to_jsonb("p_title"))))::text);

  IF v_actor_xmin IS NULL OR v_delegation_xmin IS NULL OR v_repository_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c'));
  END IF;

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'OPEN_PULL_REQUEST')) AND (v_delegation."repository_id" = (v_repository."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_repository."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_repository."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_c4bb8af190dd48efb9784efb9ff9030c'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_c4bb8af190dd48efb9784efb9ff9030c'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_c4bb8af190dd48efb9784efb9ff9030c', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_c4bb8af190dd48efb9784efb9ff9030c"(uuid, uuid, uuid, text, text, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_1388eb9f38684fa0830f60156cdba497"("p_delegation" uuid, "p_environment" uuid, "p_connector" uuid, "p_commit_sha" text, p_expected_revision text)
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
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_1388eb9f38684fa0830f60156cdba497.commitSha', 'value', pg_catalog.to_jsonb("p_commit_sha"))))::text);

  IF v_actor_xmin IS NULL OR v_delegation_xmin IS NULL OR v_environment_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_1388eb9f38684fa0830f60156cdba497'));
  END IF;

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'DEPLOY_STAGING')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_1388eb9f38684fa0830f60156cdba497'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_1388eb9f38684fa0830f60156cdba497'));
  END IF;

  IF NOT (((v_environment."tier" = 'STAGING')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_1388eb9f38684fa0830f60156cdba497.staging_target'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_1388eb9f38684fa0830f60156cdba497', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_1388eb9f38684fa0830f60156cdba497"(uuid, uuid, uuid, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_d10d1618ed4045f396b64fc3745ce3dd"("p_delegation" uuid, "p_environment" uuid, "p_connector" uuid, "p_commit_sha" text, p_expected_revision text)
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
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d10d1618ed4045f396b64fc3745ce3dd.commitSha', 'value', pg_catalog.to_jsonb("p_commit_sha"))))::text);

  IF v_actor_xmin IS NULL OR v_delegation_xmin IS NULL OR v_environment_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d10d1618ed4045f396b64fc3745ce3dd', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_d10d1618ed4045f396b64fc3745ce3dd'));
  END IF;

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_PRODUCTION_DEPLOY')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
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

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_d10d1618ed4045f396b64fc3745ce3dd"(uuid, uuid, uuid, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_411bfff32560406186bd2d442f1ecf3b"("p_delegation" uuid, "p_environment" uuid, "p_connector" uuid, "p_migration_name" text, "p_migration_sha" text, p_expected_revision text)
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
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.delegation', 'value', pg_catalog.to_jsonb("p_delegation"), 'rowVersion', pg_catalog.to_jsonb(v_delegation_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.environment', 'value', pg_catalog.to_jsonb("p_environment"), 'rowVersion', pg_catalog.to_jsonb(v_environment_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.migrationName', 'value', pg_catalog.to_jsonb("p_migration_name")), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_411bfff32560406186bd2d442f1ecf3b.migrationSha', 'value', pg_catalog.to_jsonb("p_migration_sha"))))::text);

  IF v_actor_xmin IS NULL OR v_delegation_xmin IS NULL OR v_environment_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_411bfff32560406186bd2d442f1ecf3b'));
  END IF;

  IF NOT (((((CASE WHEN (((((((((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND (v_delegation."agent_id" = (v_actor."id"))) AND (v_delegation."status" = 'ACTIVE')) AND (v_delegation."capability" = 'REQUEST_SCHEMA_MIGRATION')) AND (v_delegation."environment_id" = (v_environment."id"))) AND (v_delegation."connector_id" = (v_connector."id"))) AND (v_environment."connector_id" = (v_connector."id"))) AND (v_delegation."org_id" = v_actor."org_id")) AND (v_environment."org_id" = v_actor."org_id")) AND (v_connector."org_id" = v_actor."org_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_411bfff32560406186bd2d442f1ecf3b'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_411bfff32560406186bd2d442f1ecf3b'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_411bfff32560406186bd2d442f1ecf3b', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_411bfff32560406186bd2d442f1ecf3b"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;

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
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
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
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_047a601f15384b5ea4bfa05b5ef72676.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676'));
  END IF;

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_047a601f15384b5ea4bfa05b5ef72676'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_047a601f15384b5ea4bfa05b5ef72676'));
  END IF;

  IF NOT (((v_request."environment_tier" = 'PRODUCTION')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_047a601f15384b5ea4bfa05b5ef72676.production_request'));
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_047a601f15384b5ea4bfa05b5ef72676.awaiting_approval'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_047a601f15384b5ea4bfa05b5ef72676', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_047a601f15384b5ea4bfa05b5ef72676"(uuid, text) FROM PUBLIC;

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
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
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
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_18ab026d358144dfa4d1729e40dd832e.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e'));
  END IF;

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_18ab026d358144dfa4d1729e40dd832e'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_18ab026d358144dfa4d1729e40dd832e'));
  END IF;

  IF NOT (((v_request."environment_tier" = 'PRODUCTION')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_18ab026d358144dfa4d1729e40dd832e.production_request'));
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_18ab026d358144dfa4d1729e40dd832e.awaiting_approval'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_18ab026d358144dfa4d1729e40dd832e', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_18ab026d358144dfa4d1729e40dd832e"(uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_4c170dfcb0224cb8aaf078fe6b6ef23d"("p_request" uuid, p_expected_revision text)
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
  v_request "model_signalbox"."schema_migration_request"%ROWTYPE;
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
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d'));
  END IF;

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d'));
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_4c170dfcb0224cb8aaf078fe6b6ef23d.awaiting_approval'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4c170dfcb0224cb8aaf078fe6b6ef23d', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_4c170dfcb0224cb8aaf078fe6b6ef23d"(uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_d3a1935e42f24e4d84d25bc05ee690ad"("p_request" uuid, p_expected_revision text)
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
  v_request "model_signalbox"."schema_migration_request"%ROWTYPE;
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
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d3a1935e42f24e4d84d25bc05ee690ad.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_d3a1935e42f24e4d84d25bc05ee690ad.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad'));
  END IF;

  IF NOT (((((CASE WHEN (((((((v_actor."kind" = 'HUMAN') AND (v_actor."status" = 'ACTIVE')) AND ('APPROVER' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id")) AND ((v_actor."id") <> v_request."requested_by_id"))) IS TRUE) THEN 1 ELSE 0 END)) = 1)) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_d3a1935e42f24e4d84d25bc05ee690ad'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_d3a1935e42f24e4d84d25bc05ee690ad'));
  END IF;

  IF NOT (((v_request."status" = 'PENDING_APPROVAL')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_d3a1935e42f24e4d84d25bc05ee690ad.awaiting_approval'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_d3a1935e42f24e4d84d25bc05ee690ad', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_d3a1935e42f24e4d84d25bc05ee690ad"(uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_cbb72fd307704ab3927aa4bea8112fbf"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid, p_expected_revision text)
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
  v_request "model_signalbox"."issue_request"%ROWTYPE;
  v_request_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
  FROM "model_signalbox"."issue_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."issue_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_cbb72fd307704ab3927aa4bea8112fbf.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_allowance_xmin IS NULL OR v_request_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_cbb72fd307704ab3927aa4bea8112fbf'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_cbb72fd307704ab3927aa4bea8112fbf'));
  END IF;

  IF NOT (((v_request."status" = 'READY')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_cbb72fd307704ab3927aa4bea8112fbf.ready'));
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_cbb72fd307704ab3927aa4bea8112fbf.allowance_scope'));
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_cbb72fd307704ab3927aa4bea8112fbf.connector_active'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_cbb72fd307704ab3927aa4bea8112fbf', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_cbb72fd307704ab3927aa4bea8112fbf"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_3e99da927be642efac3d1bee026ef00a"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid, p_expected_revision text)
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
  v_request "model_signalbox"."pull_request"%ROWTYPE;
  v_request_xmin text;
  v_allowance "model_signalbox"."allowance"%ROWTYPE;
  v_allowance_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
  FROM "model_signalbox"."pull_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."pull_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT * INTO v_allowance
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT row_value.xmin::text INTO v_allowance_xmin
  FROM "model_signalbox"."allowance" AS row_value
  WHERE row_value."id" = "p_allowance";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e99da927be642efac3d1bee026ef00a.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_request_xmin IS NULL OR v_allowance_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_3e99da927be642efac3d1bee026ef00a'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_3e99da927be642efac3d1bee026ef00a'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_3e99da927be642efac3d1bee026ef00a'));
  END IF;

  IF NOT (((v_request."status" = 'READY')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_3e99da927be642efac3d1bee026ef00a.ready'));
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_3e99da927be642efac3d1bee026ef00a.allowance_scope'));
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_3e99da927be642efac3d1bee026ef00a.connector_active'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e99da927be642efac3d1bee026ef00a', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_3e99da927be642efac3d1bee026ef00a"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_3e26a4d454634bf3a2058204146d7c45"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid, p_expected_revision text)
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
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT * INTO v_request
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_3e26a4d454634bf3a2058204146d7c45.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_allowance_xmin IS NULL OR v_connector_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_3e26a4d454634bf3a2058204146d7c45'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_3e26a4d454634bf3a2058204146d7c45'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_3e26a4d454634bf3a2058204146d7c45'));
  END IF;

  IF NOT ((((v_request."environment_tier" = 'STAGING') AND (v_request."status" = 'READY'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_3e26a4d454634bf3a2058204146d7c45.staging_request'));
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_3e26a4d454634bf3a2058204146d7c45.allowance_scope'));
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_3e26a4d454634bf3a2058204146d7c45.connector_active'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_3e26a4d454634bf3a2058204146d7c45', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_3e26a4d454634bf3a2058204146d7c45"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_4a9421bfc2e744969b9f73109e6cda54"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid, p_expected_revision text)
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
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
  v_request "model_signalbox"."deployment_request"%ROWTYPE;
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

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT * INTO v_request
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."deployment_request" AS row_value
  WHERE row_value."id" = "p_request";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_4a9421bfc2e744969b9f73109e6cda54.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_allowance_xmin IS NULL OR v_connector_xmin IS NULL OR v_request_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_4a9421bfc2e744969b9f73109e6cda54'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_4a9421bfc2e744969b9f73109e6cda54'));
  END IF;

  IF NOT ((((v_request."environment_tier" = 'PRODUCTION') AND (v_request."status" = 'APPROVED'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.approved_production_request'));
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.allowance_scope'));
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_4a9421bfc2e744969b9f73109e6cda54.connector_active'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_4a9421bfc2e744969b9f73109e6cda54', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_4a9421bfc2e744969b9f73109e6cda54"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_70d3862584094631aca61e9db664d991"("p_request" uuid, "p_allowance" uuid, "p_connector" uuid, p_expected_revision text)
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
  v_request "model_signalbox"."schema_migration_request"%ROWTYPE;
  v_request_xmin text;
  v_connector "model_signalbox"."connector"%ROWTYPE;
  v_connector_xmin text;
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
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT row_value.xmin::text INTO v_request_xmin
  FROM "model_signalbox"."schema_migration_request" AS row_value
  WHERE row_value."id" = "p_request";

  SELECT * INTO v_connector
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  SELECT row_value.xmin::text INTO v_connector_xmin
  FROM "model_signalbox"."connector" AS row_value
  WHERE row_value."id" = "p_connector";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_70d3862584094631aca61e9db664d991', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.request', 'value', pg_catalog.to_jsonb("p_request"), 'rowVersion', pg_catalog.to_jsonb(v_request_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.allowance', 'value', pg_catalog.to_jsonb("p_allowance"), 'rowVersion', pg_catalog.to_jsonb(v_allowance_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_70d3862584094631aca61e9db664d991.connector', 'value', pg_catalog.to_jsonb("p_connector"), 'rowVersion', pg_catalog.to_jsonb(v_connector_xmin))))::text);

  IF v_actor_xmin IS NULL OR v_allowance_xmin IS NULL OR v_request_xmin IS NULL OR v_connector_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_70d3862584094631aca61e9db664d991'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_request."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_70d3862584094631aca61e9db664d991'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_70d3862584094631aca61e9db664d991'));
  END IF;

  IF NOT (((v_request."status" = 'APPROVED')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_70d3862584094631aca61e9db664d991.approved'));
  END IF;

  IF NOT ((((v_allowance."org_id" = v_request."org_id") AND (v_allowance."agent_id" = v_request."requested_by_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_70d3862584094631aca61e9db664d991.allowance_scope'));
  END IF;

  IF NOT (((((v_request."connector_id" = v_connector."id") AND (v_connector."org_id" = v_request."org_id")) AND (v_connector."status" = 'ACTIVE'))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_70d3862584094631aca61e9db664d991.connector_active'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_70d3862584094631aca61e9db664d991', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_70d3862584094631aca61e9db664d991"(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_5be24324b68d4c2eb334732b36e1b16c"("p_execution" uuid, "p_external_reference" text, p_expected_revision text)
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
  v_execution "model_signalbox"."execution"%ROWTYPE;
  v_execution_xmin text;
BEGIN
  SELECT identity."principal_id" INTO v_principal_id
  FROM "model_signalbox_internal"."resolve_principal_snapshot"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_execution
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution";

  SELECT row_value.xmin::text INTO v_execution_xmin
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.execution', 'value', pg_catalog.to_jsonb("p_execution"), 'rowVersion', pg_catalog.to_jsonb(v_execution_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_5be24324b68d4c2eb334732b36e1b16c.externalReference', 'value', pg_catalog.to_jsonb("p_external_reference"))))::text);

  IF v_actor_xmin IS NULL OR v_execution_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_5be24324b68d4c2eb334732b36e1b16c'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_execution."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_5be24324b68d4c2eb334732b36e1b16c'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_5be24324b68d4c2eb334732b36e1b16c'));
  END IF;

  IF NOT (((v_execution."status" = 'PENDING')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_5be24324b68d4c2eb334732b36e1b16c.pending'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_5be24324b68d4c2eb334732b36e1b16c', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_5be24324b68d4c2eb334732b36e1b16c"(uuid, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."decide_act_926686163a6544e79d44dea9336d2c88"("p_execution" uuid, "p_failure_message" text, p_expected_revision text)
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
  v_execution "model_signalbox"."execution"%ROWTYPE;
  v_execution_xmin text;
BEGIN
  SELECT identity."principal_id" INTO v_principal_id
  FROM "model_signalbox_internal"."resolve_principal_snapshot"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT row_value.xmin::text INTO v_actor_xmin
  FROM "model_signalbox"."principal" AS row_value
  WHERE row_value."id" = v_principal_id;

  SELECT * INTO v_execution
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution";

  SELECT row_value.xmin::text INTO v_execution_xmin
  FROM "model_signalbox"."execution" AS row_value
  WHERE row_value."id" = "p_execution";

  v_revision := 'rev:1:' || pg_catalog.md5(pg_catalog.jsonb_build_object('sourceHash', 'sha256:f5b2d9c53f816a26d113584ee7bec33cbca55ef28b95a53b375e2c234cd3d5b9', 'operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'components', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_926686163a6544e79d44dea9336d2c88.actor', 'value', pg_catalog.to_jsonb(v_principal_id), 'rowVersion', pg_catalog.to_jsonb(v_actor_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_926686163a6544e79d44dea9336d2c88.execution', 'value', pg_catalog.to_jsonb("p_execution"), 'rowVersion', pg_catalog.to_jsonb(v_execution_xmin)), pg_catalog.jsonb_build_object('parameterId', 'parameter:action:act_926686163a6544e79d44dea9336d2c88.failureMessage', 'value', pg_catalog.to_jsonb("p_failure_message"))))::text);

  IF v_actor_xmin IS NULL OR v_execution_xmin IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_926686163a6544e79d44dea9336d2c88'));
  END IF;

  IF NOT ((((((v_actor."kind" = 'AGENT') AND (v_actor."status" = 'ACTIVE')) AND ('EXECUTOR' = ANY(v_actor."roles"))) AND (v_actor."org_id" = v_execution."org_id"))) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'status', 'denied', 'applicable', FALSE, 'authority', 'none', 'explanation', pg_catalog.jsonb_build_object('kind', 'authorization', 'ruleId', 'authorize:action:act_926686163a6544e79d44dea9336d2c88'));
  END IF;

  IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM v_revision THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'status', 'stale', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'revision', 'ruleId', 'revision:action:act_926686163a6544e79d44dea9336d2c88'));
  END IF;

  IF NOT (((v_execution."status" = 'PENDING')) IS TRUE) THEN
    RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'status', 'notApplicable', 'applicable', FALSE, 'authority', 'none', 'revision', v_revision, 'explanation', pg_catalog.jsonb_build_object('kind', 'requirement', 'ruleId', 'require:action:act_926686163a6544e79d44dea9336d2c88.pending'));
  END IF;

  RETURN pg_catalog.jsonb_build_object('operationId', 'action:act_926686163a6544e79d44dea9336d2c88', 'status', 'applicable', 'applicable', TRUE, 'authority', 'none', 'revision', v_revision);
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_926686163a6544e79d44dea9336d2c88"(uuid, text, text) FROM PUBLIC;

RESET ROLE;
