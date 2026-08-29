-- Generated guarded query functions. Caller identity is resolved from direct login or transaction-bound gateway context.
SET ROLE modellang_owner;

CREATE OR REPLACE FUNCTION "model_signalbox"."my_org_deploy_requests"(p_cursor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_result jsonb;
  v_identity_issuer text;
  v_identity_subject text;
  v_cursor_json jsonb;
  v_cursor_sort "model_signalbox"."production_deploy_request"."id"%TYPE;
  v_cursor_identity uuid;
  v_input_hash text;
  v_actor "model_signalbox"."principal"%ROWTYPE;
BEGIN
  SELECT identity."principal_id", identity."identity_issuer", identity."identity_subject"
  INTO v_principal_id, v_identity_issuer, v_identity_subject
  FROM "model_signalbox_internal"."resolve_principal"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal"
  WHERE "id" = v_principal_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:query:qry_60d1c5d416eb428caa385db274edcb4b';
  END IF;

  IF NOT ((TRUE) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:query:qry_60d1c5d416eb428caa385db274edcb4b';
  END IF;

  v_input_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object(
    'caller', pg_catalog.to_jsonb(v_principal_id),
    'inputs', pg_catalog.jsonb_build_object()
  ))::text, 'UTF8')), 'hex');

  IF p_cursor IS NOT NULL THEN
    BEGIN
      IF pg_catalog.length(p_cursor) < 1 OR pg_catalog.length(p_cursor) > 4096 OR p_cursor !~ '^[A-Za-z0-9_-]+$' THEN
        RAISE EXCEPTION 'invalid cursor';
      END IF;
      v_cursor_json := pg_catalog.convert_from(
        pg_catalog.decode(pg_catalog.translate(p_cursor, '-_', '+/') || pg_catalog.repeat('=', (4 - pg_catalog.length(p_cursor) % 4) % 4), 'base64'),
        'UTF8'
      )::jsonb;
      IF pg_catalog.jsonb_typeof(v_cursor_json) IS DISTINCT FROM 'object'
        OR (SELECT pg_catalog.count(*) FROM pg_catalog.jsonb_object_keys(v_cursor_json)) <> 11
        OR (v_cursor_json -> 'v') IS DISTINCT FROM '1'::jsonb
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'modelId') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'modelVersion') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'sourceHash') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'queryId') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'revision') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'orderFieldId') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'direction') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'inputHash') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'sort') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'identity') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'invalid cursor';
      END IF;
      v_cursor_sort := v_cursor_json ->> 'sort';
      v_cursor_identity := (v_cursor_json ->> 'identity')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:cursor:query:qry_60d1c5d416eb428caa385db274edcb4b';
    END;

    IF v_cursor_json ->> 'modelId' IS DISTINCT FROM 'model:Signalbox'
      OR v_cursor_json ->> 'modelVersion' IS DISTINCT FROM '0.50.0'
      OR v_cursor_json ->> 'sourceHash' IS DISTINCT FROM 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e'
      OR v_cursor_json ->> 'queryId' IS DISTINCT FROM 'query:qry_60d1c5d416eb428caa385db274edcb4b'
      OR v_cursor_json ->> 'revision' IS DISTINCT FROM 'sha256:e07638c9b2a5d43087667ad7cdde7d46a6b3cb306f8d2e539a3b11848729cc8b'
      OR v_cursor_json ->> 'orderFieldId' IS DISTINCT FROM 'field:fld_adecbdc3c4cb4bbb8b4e528dbc7408a5'
      OR v_cursor_json ->> 'direction' IS DISTINCT FROM 'asc'
      OR v_cursor_json ->> 'inputHash' IS DISTINCT FROM v_input_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:cursor:query:qry_60d1c5d416eb428caa385db274edcb4b';
    END IF;
  END IF;

  WITH page_rows AS MATERIALIZED (
    SELECT jsonb_build_object('id', v_row."id", 'createdAt', v_row."created_at", 'commitSha', v_row."commit_sha", 'status', v_row."status", 'requestedBy', (SELECT jsonb_build_object('id', "v_projection_4"."id", 'displayName', "v_projection_4"."display_name", 'kind', "v_projection_4"."kind") FROM "model_signalbox"."principal" AS "v_projection_4" WHERE "v_projection_4"."id" = v_row."requested_by_id"), 'approvedBy', CASE WHEN v_row."approved_by_id" IS NULL THEN NULL ELSE (SELECT jsonb_build_object('id', "v_projection_5"."id", 'displayName', "v_projection_5"."display_name", 'kind', "v_projection_5"."kind") FROM "model_signalbox"."principal" AS "v_projection_5" WHERE "v_projection_5"."id" = v_row."approved_by_id") END) AS "item",
           v_row."id" AS "sort_value",
           v_row."id" AS "identity"
    FROM "model_signalbox"."production_deploy_request" AS v_row
    WHERE (((v_row."org_id" = v_actor."org_id")) IS TRUE)
      AND (p_cursor IS NULL
        OR (v_row."id" > v_cursor_sort OR (v_row."id" = v_cursor_sort AND v_row."id" > v_cursor_identity)))
    ORDER BY v_row."id" ASC, v_row."id" ASC
    LIMIT 51
  ), visible_rows AS MATERIALIZED (
    SELECT * FROM page_rows
    ORDER BY "sort_value" ASC, "identity" ASC
    LIMIT 50
  )
  SELECT pg_catalog.jsonb_build_object(
    'items', COALESCE((
      SELECT pg_catalog.jsonb_agg("item" ORDER BY "sort_value" ASC, "identity" ASC)
      FROM visible_rows
    ), '[]'::jsonb),
    'nextCursor', CASE WHEN (SELECT pg_catalog.count(*) FROM page_rows) > 50 THEN (
      SELECT pg_catalog.rtrim(pg_catalog.translate(pg_catalog.replace(pg_catalog.encode(pg_catalog.convert_to((pg_catalog.jsonb_build_object('v', 1, 'modelId', 'model:Signalbox', 'modelVersion', '0.50.0', 'sourceHash', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'queryId', 'query:qry_60d1c5d416eb428caa385db274edcb4b', 'revision', 'sha256:e07638c9b2a5d43087667ad7cdde7d46a6b3cb306f8d2e539a3b11848729cc8b', 'orderFieldId', 'field:fld_adecbdc3c4cb4bbb8b4e528dbc7408a5', 'direction', 'asc', 'inputHash', v_input_hash, 'sort', ("sort_value")::text, 'identity', ("identity")::text))::text, 'UTF8'), 'base64'), E'\n', ''), '+/', '-_'), '=')
      FROM visible_rows
      ORDER BY "sort_value" DESC, "identity" DESC
      LIMIT 1
    ) ELSE NULL END
  ) INTO v_result;

  INSERT INTO "model_signalbox_internal"."query_audit" ("query_id", "database_principal", "principal_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "query_revision", "request_hash", "response_hash", "result_count", "sort_profile", "continued")
  VALUES ('query:qry_60d1c5d416eb428caa385db274edcb4b', session_user, v_principal_id, v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.50.0', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'sha256:e07638c9b2a5d43087667ad7cdde7d46a6b3cb306f8d2e539a3b11848729cc8b', 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('queryId', 'query:qry_60d1c5d416eb428caa385db274edcb4b', 'revision', 'sha256:e07638c9b2a5d43087667ad7cdde7d46a6b3cb306f8d2e539a3b11848729cc8b', 'inputs', pg_catalog.jsonb_build_object(), 'sortProfile', pg_catalog.to_jsonb('default'::text), 'cursor', pg_catalog.to_jsonb(p_cursor)))::text, 'UTF8')), 'hex'), 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((v_result)::text, 'UTF8')), 'hex'), pg_catalog.jsonb_array_length(v_result -> 'items'), 'default', p_cursor IS NOT NULL);

  RETURN v_result;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."my_org_deploy_requests"(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION "model_signalbox"."approval_inbox"(p_cursor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $modellang$
DECLARE
  v_principal_id uuid;
  v_result jsonb;
  v_identity_issuer text;
  v_identity_subject text;
  v_cursor_json jsonb;
  v_cursor_sort "model_signalbox"."production_deploy_request"."id"%TYPE;
  v_cursor_identity uuid;
  v_input_hash text;
  v_actor "model_signalbox"."principal"%ROWTYPE;
BEGIN
  SELECT identity."principal_id", identity."identity_issuer", identity."identity_subject"
  INTO v_principal_id, v_identity_issuer, v_identity_subject
  FROM "model_signalbox_internal"."resolve_principal"() AS identity;

  SELECT * INTO v_actor
  FROM "model_signalbox"."principal"
  WHERE "id" = v_principal_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:query:qry_21f24f72d72c4bb98df539477f0e81f2';
  END IF;

  IF NOT ((((v_actor."kind" = 'HUMAN') AND ('APPROVER' = ANY(v_actor."roles")))) IS TRUE) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'ML_AUTHORIZATION:authorize:query:qry_21f24f72d72c4bb98df539477f0e81f2';
  END IF;

  v_input_hash := 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object(
    'caller', pg_catalog.to_jsonb(v_principal_id),
    'inputs', pg_catalog.jsonb_build_object()
  ))::text, 'UTF8')), 'hex');

  IF p_cursor IS NOT NULL THEN
    BEGIN
      IF pg_catalog.length(p_cursor) < 1 OR pg_catalog.length(p_cursor) > 4096 OR p_cursor !~ '^[A-Za-z0-9_-]+$' THEN
        RAISE EXCEPTION 'invalid cursor';
      END IF;
      v_cursor_json := pg_catalog.convert_from(
        pg_catalog.decode(pg_catalog.translate(p_cursor, '-_', '+/') || pg_catalog.repeat('=', (4 - pg_catalog.length(p_cursor) % 4) % 4), 'base64'),
        'UTF8'
      )::jsonb;
      IF pg_catalog.jsonb_typeof(v_cursor_json) IS DISTINCT FROM 'object'
        OR (SELECT pg_catalog.count(*) FROM pg_catalog.jsonb_object_keys(v_cursor_json)) <> 11
        OR (v_cursor_json -> 'v') IS DISTINCT FROM '1'::jsonb
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'modelId') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'modelVersion') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'sourceHash') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'queryId') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'revision') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'orderFieldId') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'direction') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'inputHash') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'sort') IS DISTINCT FROM 'string'
        OR pg_catalog.jsonb_typeof(v_cursor_json -> 'identity') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'invalid cursor';
      END IF;
      v_cursor_sort := v_cursor_json ->> 'sort';
      v_cursor_identity := (v_cursor_json ->> 'identity')::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ML_VALIDATION:cursor:query:qry_21f24f72d72c4bb98df539477f0e81f2';
    END;

    IF v_cursor_json ->> 'modelId' IS DISTINCT FROM 'model:Signalbox'
      OR v_cursor_json ->> 'modelVersion' IS DISTINCT FROM '0.50.0'
      OR v_cursor_json ->> 'sourceHash' IS DISTINCT FROM 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e'
      OR v_cursor_json ->> 'queryId' IS DISTINCT FROM 'query:qry_21f24f72d72c4bb98df539477f0e81f2'
      OR v_cursor_json ->> 'revision' IS DISTINCT FROM 'sha256:1be0f20f5159288d02fcc0cc3848d32633b1c7bcad6dea570b6b61a0ed5ac15a'
      OR v_cursor_json ->> 'orderFieldId' IS DISTINCT FROM 'field:fld_adecbdc3c4cb4bbb8b4e528dbc7408a5'
      OR v_cursor_json ->> 'direction' IS DISTINCT FROM 'asc'
      OR v_cursor_json ->> 'inputHash' IS DISTINCT FROM v_input_hash THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'ML_STALE:cursor:query:qry_21f24f72d72c4bb98df539477f0e81f2';
    END IF;
  END IF;

  WITH page_rows AS MATERIALIZED (
    SELECT jsonb_build_object('id', v_row."id", 'createdAt', v_row."created_at", 'commitSha', v_row."commit_sha", 'status', v_row."status", 'requestedBy', (SELECT jsonb_build_object('id', "v_projection_4"."id", 'displayName', "v_projection_4"."display_name", 'kind', "v_projection_4"."kind") FROM "model_signalbox"."principal" AS "v_projection_4" WHERE "v_projection_4"."id" = v_row."requested_by_id"), 'approvedBy', CASE WHEN v_row."approved_by_id" IS NULL THEN NULL ELSE (SELECT jsonb_build_object('id', "v_projection_5"."id", 'displayName', "v_projection_5"."display_name", 'kind', "v_projection_5"."kind") FROM "model_signalbox"."principal" AS "v_projection_5" WHERE "v_projection_5"."id" = v_row."approved_by_id") END) AS "item",
           v_row."id" AS "sort_value",
           v_row."id" AS "identity"
    FROM "model_signalbox"."production_deploy_request" AS v_row
    WHERE (((((v_row."org_id" = v_actor."org_id") AND (v_row."status" = 'PENDING_APPROVAL')) AND (v_row."requested_by_id" <> v_actor."id"))) IS TRUE)
      AND (p_cursor IS NULL
        OR (v_row."id" > v_cursor_sort OR (v_row."id" = v_cursor_sort AND v_row."id" > v_cursor_identity)))
    ORDER BY v_row."id" ASC, v_row."id" ASC
    LIMIT 51
  ), visible_rows AS MATERIALIZED (
    SELECT * FROM page_rows
    ORDER BY "sort_value" ASC, "identity" ASC
    LIMIT 50
  )
  SELECT pg_catalog.jsonb_build_object(
    'items', COALESCE((
      SELECT pg_catalog.jsonb_agg("item" ORDER BY "sort_value" ASC, "identity" ASC)
      FROM visible_rows
    ), '[]'::jsonb),
    'nextCursor', CASE WHEN (SELECT pg_catalog.count(*) FROM page_rows) > 50 THEN (
      SELECT pg_catalog.rtrim(pg_catalog.translate(pg_catalog.replace(pg_catalog.encode(pg_catalog.convert_to((pg_catalog.jsonb_build_object('v', 1, 'modelId', 'model:Signalbox', 'modelVersion', '0.50.0', 'sourceHash', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'queryId', 'query:qry_21f24f72d72c4bb98df539477f0e81f2', 'revision', 'sha256:1be0f20f5159288d02fcc0cc3848d32633b1c7bcad6dea570b6b61a0ed5ac15a', 'orderFieldId', 'field:fld_adecbdc3c4cb4bbb8b4e528dbc7408a5', 'direction', 'asc', 'inputHash', v_input_hash, 'sort', ("sort_value")::text, 'identity', ("identity")::text))::text, 'UTF8'), 'base64'), E'\n', ''), '+/', '-_'), '=')
      FROM visible_rows
      ORDER BY "sort_value" DESC, "identity" DESC
      LIMIT 1
    ) ELSE NULL END
  ) INTO v_result;

  INSERT INTO "model_signalbox_internal"."query_audit" ("query_id", "database_principal", "principal_id", "identity_issuer", "identity_subject", "model_id", "model_version", "source_hash", "query_revision", "request_hash", "response_hash", "result_count", "sort_profile", "continued")
  VALUES ('query:qry_21f24f72d72c4bb98df539477f0e81f2', session_user, v_principal_id, v_identity_issuer, v_identity_subject, 'model:Signalbox', '0.50.0', 'sha256:c05d742f0b6c8e9a06ee09732d45a9e73af1e8508dfe2d2ee1706df175c6356e', 'sha256:1be0f20f5159288d02fcc0cc3848d32633b1c7bcad6dea570b6b61a0ed5ac15a', 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((pg_catalog.jsonb_build_object('queryId', 'query:qry_21f24f72d72c4bb98df539477f0e81f2', 'revision', 'sha256:1be0f20f5159288d02fcc0cc3848d32633b1c7bcad6dea570b6b61a0ed5ac15a', 'inputs', pg_catalog.jsonb_build_object(), 'sortProfile', pg_catalog.to_jsonb('default'::text), 'cursor', pg_catalog.to_jsonb(p_cursor)))::text, 'UTF8')), 'hex'), 'sha256:' || pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to((v_result)::text, 'UTF8')), 'hex'), pg_catalog.jsonb_array_length(v_result -> 'items'), 'default', p_cursor IS NOT NULL);

  RETURN v_result;
END
$modellang$;

REVOKE ALL ON FUNCTION "model_signalbox"."approval_inbox"(text) FROM PUBLIC;

RESET ROLE;
