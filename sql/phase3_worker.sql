-- Signalbox Phase 3 durable execution claims. Apply after Phase 2 auth SQL.
CREATE SCHEMA IF NOT EXISTS model_signalbox_worker AUTHORIZATION modellang_owner;
SET ROLE modellang_owner;

ALTER SCHEMA model_signalbox_worker OWNER TO modellang_owner;
REVOKE ALL ON SCHEMA model_signalbox_worker FROM PUBLIC;

CREATE TABLE IF NOT EXISTS model_signalbox_worker.execution_claim (
  execution_id uuid PRIMARY KEY REFERENCES model_signalbox.execution(id) ON DELETE CASCADE,
  worker_id text NOT NULL,
  claim_token uuid NOT NULL,
  attempt_count integer NOT NULL,
  claimed_at timestamptz NOT NULL,
  leased_until timestamptz NOT NULL,
  next_attempt_at timestamptz NOT NULL,
  last_error_code text,
  effect_reference text,
  CONSTRAINT ck_execution_claim_worker CHECK (pg_catalog.char_length(worker_id) BETWEEN 1 AND 128),
  CONSTRAINT ck_execution_claim_attempt CHECK (attempt_count >= 1),
  CONSTRAINT ck_execution_claim_lease CHECK (leased_until > claimed_at),
  CONSTRAINT ck_execution_claim_error CHECK (
    last_error_code IS NULL OR last_error_code ~ '^[A-Z][A-Z0-9_]{0,63}$'
  ),
  CONSTRAINT ck_execution_claim_reference CHECK (
    effect_reference IS NULL OR pg_catalog.char_length(effect_reference) BETWEEN 1 AND 2048
  )
);
CREATE INDEX IF NOT EXISTS ix_execution_claim_ready
  ON model_signalbox_worker.execution_claim(next_attempt_at, leased_until);
REVOKE ALL ON TABLE model_signalbox_worker.execution_claim FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_worker.claim_execution(
  p_issuer text,
  p_subject text,
  p_worker_id text,
  p_lease_seconds integer
)
RETURNS TABLE (
  execution_id uuid,
  claim_token uuid,
  attempt_count integer,
  last_error_code text,
  effect_reference text,
  request_kind text,
  connector_id uuid,
  connector_kind text,
  payload jsonb,
  correlation_id text,
  causation_id text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_actor_id uuid;
  v_actor_org_id uuid;
  v_execution_id uuid;
  v_request_id uuid;
  v_request_kind text;
  v_connector_id uuid;
  v_connector_kind text;
  v_claim_token uuid;
  v_attempt_count integer;
  v_last_error_code text;
  v_effect_reference text;
  v_payload jsonb;
  v_correlation_id text;
  v_causation_id text;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  IF p_worker_id IS NULL OR pg_catalog.char_length(p_worker_id) NOT BETWEEN 1 AND 128
     OR p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 5 AND 300 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'SB_VALIDATION:worker_claim';
  END IF;

  SELECT principal.id, principal.org_id
  INTO v_actor_id, v_actor_org_id
  FROM model_signalbox_internal.gateway_principal_binding AS binding
  JOIN model_signalbox.principal AS principal ON principal.id = binding.principal_id
  WHERE binding.issuer = p_issuer
    AND binding.subject = p_subject
    AND principal.kind = 'AGENT'
    AND principal.status = 'ACTIVE'
    AND 'EXECUTOR' = ANY(principal.roles)
  FOR SHARE OF principal;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:execution_worker';
  END IF;

  SELECT execution.id, execution.request_id, execution.request_kind,
         execution.connector_id, connector.kind
  INTO v_execution_id, v_request_id, v_request_kind, v_connector_id, v_connector_kind
  FROM model_signalbox.execution AS execution
  JOIN model_signalbox.connector AS connector
    ON connector.id = execution.connector_id
   AND connector.org_id = execution.org_id
   AND connector.status = 'ACTIVE'
  LEFT JOIN model_signalbox_worker.execution_claim AS existing
    ON existing.execution_id = execution.id
  WHERE execution.org_id = v_actor_org_id
    AND execution.status = 'PENDING'
    AND (
      existing.execution_id IS NULL
      OR (
        existing.leased_until <= pg_catalog.transaction_timestamp()
        AND existing.next_attempt_at <= pg_catalog.transaction_timestamp()
      )
    )
  ORDER BY execution.started_at, execution.id
  FOR UPDATE OF execution SKIP LOCKED
  LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  INSERT INTO model_signalbox_worker.execution_claim AS claim
    (execution_id, worker_id, claim_token, attempt_count, claimed_at, leased_until, next_attempt_at, last_error_code)
  VALUES
    (
      v_execution_id,
      p_worker_id,
      pg_catalog.gen_random_uuid(),
      1,
      pg_catalog.transaction_timestamp(),
      pg_catalog.transaction_timestamp() + pg_catalog.make_interval(secs => p_lease_seconds),
      pg_catalog.transaction_timestamp(),
      NULL
    )
  ON CONFLICT ON CONSTRAINT execution_claim_pkey DO UPDATE
  SET worker_id = EXCLUDED.worker_id,
      claim_token = EXCLUDED.claim_token,
      attempt_count = claim.attempt_count + 1,
      claimed_at = EXCLUDED.claimed_at,
      leased_until = EXCLUDED.leased_until,
      next_attempt_at = EXCLUDED.next_attempt_at
  RETURNING claim.claim_token, claim.attempt_count, claim.last_error_code, claim.effect_reference
  INTO v_claim_token, v_attempt_count, v_last_error_code, v_effect_reference;

  CASE v_request_kind
    WHEN 'ISSUE' THEN
      SELECT pg_catalog.jsonb_build_object(
        'requestId', request.id,
        'owner', repository.owner,
        'repository', repository.name,
        'title', request.title,
        'body', request.body
      )
      INTO v_payload
      FROM model_signalbox.issue_request AS request
      JOIN model_signalbox.repository AS repository
        ON repository.id = request.repository_id
       AND repository.org_id = request.org_id
       AND repository.connector_id = request.connector_id
      WHERE request.id = v_request_id
        AND request.org_id = v_actor_org_id
        AND request.connector_id = v_connector_id
        AND request.status = 'DISPATCHED';
    WHEN 'PULL_REQUEST' THEN
      SELECT pg_catalog.jsonb_build_object(
        'requestId', request.id,
        'owner', repository.owner,
        'repository', repository.name,
        'headBranch', request.head_branch,
        'baseBranch', request.base_branch,
        'title', request.title
      )
      INTO v_payload
      FROM model_signalbox.pull_request AS request
      JOIN model_signalbox.repository AS repository
        ON repository.id = request.repository_id
       AND repository.org_id = request.org_id
       AND repository.connector_id = request.connector_id
      WHERE request.id = v_request_id
        AND request.org_id = v_actor_org_id
        AND request.connector_id = v_connector_id
        AND request.status = 'DISPATCHED';
    WHEN 'DEPLOYMENT' THEN
      SELECT pg_catalog.jsonb_build_object(
        'requestId', request.id,
        'environmentId', environment.id,
        'environmentName', environment.name,
        'environmentTier', request.environment_tier,
        'owner', repository.owner,
        'repository', repository.name,
        'commitSha', request.commit_sha
      )
      INTO v_payload
      FROM model_signalbox.deployment_request AS request
      JOIN model_signalbox.environment AS environment
        ON environment.id = request.environment_id
       AND environment.org_id = request.org_id
       AND environment.connector_id = request.connector_id
      JOIN model_signalbox.repository AS repository
        ON repository.id = environment.repository_id
       AND repository.org_id = request.org_id
      WHERE request.id = v_request_id
        AND request.org_id = v_actor_org_id
        AND request.connector_id = v_connector_id
        AND request.status = 'DISPATCHED';
    WHEN 'SCHEMA_MIGRATION' THEN
      SELECT pg_catalog.jsonb_build_object(
        'requestId', request.id,
        'environmentId', environment.id,
        'environmentName', environment.name,
        'owner', repository.owner,
        'repository', repository.name,
        'migrationName', request.migration_name,
        'migrationSha', request.migration_sha
      )
      INTO v_payload
      FROM model_signalbox.schema_migration_request AS request
      JOIN model_signalbox.environment AS environment
        ON environment.id = request.environment_id
       AND environment.org_id = request.org_id
       AND environment.connector_id = request.connector_id
      JOIN model_signalbox.repository AS repository
        ON repository.id = environment.repository_id
       AND repository.org_id = request.org_id
      WHERE request.id = v_request_id
        AND request.org_id = v_actor_org_id
        AND request.connector_id = v_connector_id
        AND request.status = 'DISPATCHED';
    ELSE
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'SB_VALIDATION:request_kind';
  END CASE;

  IF v_payload IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:execution_payload';
  END IF;

  SELECT audit.correlation_id, audit.causation_id
  INTO v_correlation_id, v_causation_id
  FROM model_signalbox_internal.action_audit AS audit
  WHERE audit.target_id = v_execution_id
    AND audit.action_id IN (
      'action:act_cbb72fd307704ab3927aa4bea8112fbf',
      'action:act_3e99da927be642efac3d1bee026ef00a',
      'action:act_3e26a4d454634bf3a2058204146d7c45',
      'action:act_4a9421bfc2e744969b9f73109e6cda54',
      'action:act_70d3862584094631aca61e9db664d991'
    )
  ORDER BY audit.id DESC
  LIMIT 1;

  RETURN QUERY SELECT
    v_execution_id,
    v_claim_token,
    v_attempt_count,
    v_last_error_code,
    v_effect_reference,
    v_request_kind,
    v_connector_id,
    v_connector_kind,
    v_payload,
    v_correlation_id,
    v_causation_id;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_worker.claim_execution(text, text, text, integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_worker.confirm_execution_claim(
  p_issuer text,
  p_subject text,
  p_worker_id text,
  p_execution_id uuid,
  p_claim_token uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_confirmed boolean;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  SELECT EXISTS (
    SELECT 1
    FROM model_signalbox_worker.execution_claim AS claim
    JOIN model_signalbox.execution AS execution ON execution.id = claim.execution_id
    JOIN model_signalbox.connector AS connector
      ON connector.id = execution.connector_id
     AND connector.org_id = execution.org_id
    JOIN model_signalbox_internal.gateway_principal_binding AS binding
      ON binding.issuer = p_issuer AND binding.subject = p_subject
    JOIN model_signalbox.principal AS principal
      ON principal.id = binding.principal_id
     AND principal.org_id = execution.org_id
    WHERE claim.execution_id = p_execution_id
      AND claim.claim_token = p_claim_token
      AND claim.worker_id = p_worker_id
      AND claim.leased_until > pg_catalog.transaction_timestamp()
      AND execution.status = 'PENDING'
      AND connector.status = 'ACTIVE'
      AND principal.kind = 'AGENT'
      AND principal.status = 'ACTIVE'
      AND 'EXECUTOR' = ANY(principal.roles)
  ) INTO v_confirmed;
  RETURN v_confirmed;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_worker.confirm_execution_claim(text, text, text, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_worker.record_execution_effect(
  p_worker_id text,
  p_execution_id uuid,
  p_claim_token uuid,
  p_effect_reference text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_updated integer;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  IF p_effect_reference IS NULL OR pg_catalog.char_length(p_effect_reference) NOT BETWEEN 1 AND 2048 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'SB_VALIDATION:effect_reference';
  END IF;
  UPDATE model_signalbox_worker.execution_claim AS claim
  SET effect_reference = p_effect_reference
  WHERE claim.execution_id = p_execution_id
    AND claim.claim_token = p_claim_token
    AND claim.worker_id = p_worker_id
    AND (claim.effect_reference IS NULL OR claim.effect_reference = p_effect_reference);
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_worker.record_execution_effect(text, uuid, uuid, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_worker.release_execution_claim(
  p_worker_id text,
  p_execution_id uuid,
  p_claim_token uuid,
  p_error_code text,
  p_delay_seconds integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_updated integer;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  IF p_error_code IS NULL OR p_error_code !~ '^[A-Z][A-Z0-9_]{0,63}$'
     OR p_delay_seconds IS NULL OR p_delay_seconds NOT BETWEEN 0 AND 3600 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'SB_VALIDATION:worker_release';
  END IF;
  UPDATE model_signalbox_worker.execution_claim AS claim
  SET leased_until = pg_catalog.transaction_timestamp(),
      next_attempt_at = pg_catalog.transaction_timestamp() + pg_catalog.make_interval(secs => p_delay_seconds),
      last_error_code = p_error_code
  WHERE claim.execution_id = p_execution_id
    AND claim.claim_token = p_claim_token
    AND claim.worker_id = p_worker_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_worker.release_execution_claim(text, uuid, uuid, text, integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_worker.finish_execution_claim(
  p_worker_id text,
  p_execution_id uuid,
  p_claim_token uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_deleted integer;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  DELETE FROM model_signalbox_worker.execution_claim AS claim
  WHERE claim.execution_id = p_execution_id
    AND claim.claim_token = p_claim_token
    AND claim.worker_id = p_worker_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted = 1;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_worker.finish_execution_claim(text, uuid, uuid) FROM PUBLIC;

GRANT USAGE ON SCHEMA model_signalbox_worker TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_worker.claim_execution(text, text, text, integer) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_worker.confirm_execution_claim(text, text, text, uuid, uuid) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_worker.record_execution_effect(text, uuid, uuid, text) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_worker.release_execution_claim(text, uuid, uuid, text, integer) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_worker.finish_execution_claim(text, uuid, uuid) TO modellang_gateway;

RESET ROLE;
