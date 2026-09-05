BEGIN;

CREATE SCHEMA IF NOT EXISTS signalbox_architecture;

CREATE TABLE IF NOT EXISTS signalbox_architecture.object_artifact (
  id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('MODEL_SOURCE', 'GOVERNANCE_BUNDLE', 'DIFF', 'LOG', 'OTHER')),
  object_key text NOT NULL,
  sha256 text NOT NULL CHECK (sha256 ~ '^sha256:[0-9a-f]{64}$'),
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  content_type text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE (org_id, object_key),
  UNIQUE (org_id, kind, sha256)
);

CREATE TABLE IF NOT EXISTS signalbox_architecture.governance_bundle (
  id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  model_name text NOT NULL,
  model_version text NOT NULL,
  source_hash text NOT NULL CHECK (source_hash ~ '^sha256:[0-9a-f]{64}$'),
  bundle_hash text NOT NULL CHECK (bundle_hash ~ '^sha256:[0-9a-f]{64}$'),
  compiler_version text NOT NULL,
  runtime_compatibility text NOT NULL,
  source_artifact_id uuid NOT NULL REFERENCES signalbox_architecture.object_artifact(id),
  bundle_artifact_id uuid NOT NULL REFERENCES signalbox_architecture.object_artifact(id),
  operation_ids jsonb NOT NULL CHECK (jsonb_typeof(operation_ids) = 'array'),
  status text NOT NULL CHECK (status IN ('COMPILED', 'ACTIVE', 'RETIRED')),
  previous_bundle_id uuid REFERENCES signalbox_architecture.governance_bundle(id),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  activated_by uuid,
  activated_at timestamptz,
  CHECK ((status = 'ACTIVE' AND activated_at IS NOT NULL) OR status <> 'ACTIVE'),
  UNIQUE (org_id, source_hash)
);

CREATE UNIQUE INDEX IF NOT EXISTS governance_bundle_one_active_per_org
  ON signalbox_architecture.governance_bundle(org_id)
  WHERE status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS signalbox_architecture.execution_profile (
  id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  name text NOT NULL,
  version text NOT NULL,
  provider text NOT NULL,
  image_digest text NOT NULL,
  configuration_hash text NOT NULL CHECK (configuration_hash ~ '^sha256:[0-9a-f]{64}$'),
  configuration jsonb NOT NULL CHECK (jsonb_typeof(configuration) = 'object'),
  status text NOT NULL CHECK (status IN ('ACTIVE', 'RETIRED')),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE (org_id, name, version),
  UNIQUE (org_id, configuration_hash)
);

CREATE TABLE IF NOT EXISTS signalbox_architecture.capability_binding (
  org_id uuid NOT NULL,
  bundle_id uuid NOT NULL REFERENCES signalbox_architecture.governance_bundle(id),
  operation_id text NOT NULL,
  runtime_supported boolean NOT NULL,
  resource_bound boolean NOT NULL,
  connector_bound boolean NOT NULL,
  connector_active boolean NOT NULL,
  credential_ready boolean NOT NULL,
  execution_profile_ready boolean NOT NULL,
  delegation_active boolean NOT NULL,
  quota_available boolean NOT NULL,
  policy_discoverable boolean NOT NULL,
  missing_details jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(missing_details) = 'array'),
  checked_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  PRIMARY KEY (org_id, bundle_id, operation_id)
);

CREATE TABLE IF NOT EXISTS signalbox_architecture.run_manifest (
  id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  agent_id uuid NOT NULL,
  bundle_id uuid NOT NULL REFERENCES signalbox_architecture.governance_bundle(id),
  execution_profile_id uuid NOT NULL REFERENCES signalbox_architecture.execution_profile(id),
  manifest_hash text NOT NULL CHECK (manifest_hash ~ '^sha256:[0-9a-f]{64}$'),
  manifest jsonb NOT NULL CHECK (jsonb_typeof(manifest) = 'object'),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE (org_id, manifest_hash)
);

CREATE TABLE IF NOT EXISTS signalbox_architecture.agent_run (
  id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  manifest_id uuid NOT NULL UNIQUE REFERENCES signalbox_architecture.run_manifest(id),
  state text NOT NULL CHECK (state IN (
    'QUEUED', 'RESOLVING', 'PREPARING_ENVIRONMENT', 'PLANNING', 'OPERATING',
    'AWAITING_APPROVAL', 'EXECUTING_EFFECT', 'VERIFYING', 'COMPLETED', 'FAILED',
    'CANCELLED', 'TIMED_OUT', 'BUDGET_EXHAUSTED', 'PREPARATION_FAILED', 'RECOVERY_REQUIRED'
  )),
  state_version bigint NOT NULL DEFAULT 0 CHECK (state_version >= 0),
  lease_owner text,
  lease_expires_at timestamptz,
  failure_code text,
  failure_detail text,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  completed_at timestamptz,
  CHECK (
    (state IN ('COMPLETED', 'FAILED', 'CANCELLED', 'TIMED_OUT', 'BUDGET_EXHAUSTED', 'PREPARATION_FAILED', 'RECOVERY_REQUIRED') AND completed_at IS NOT NULL)
    OR
    (state NOT IN ('COMPLETED', 'FAILED', 'CANCELLED', 'TIMED_OUT', 'BUDGET_EXHAUSTED', 'PREPARATION_FAILED', 'RECOVERY_REQUIRED') AND completed_at IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS agent_run_claimable
  ON signalbox_architecture.agent_run(state, lease_expires_at, created_at);

CREATE TABLE IF NOT EXISTS signalbox_architecture.run_transition (
  run_id uuid NOT NULL REFERENCES signalbox_architecture.agent_run(id),
  sequence bigint NOT NULL,
  from_state text,
  to_state text NOT NULL,
  evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence) = 'object'),
  occurred_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  PRIMARY KEY (run_id, sequence)
);

CREATE TABLE IF NOT EXISTS signalbox_architecture.sandbox_operation (
  run_id uuid NOT NULL REFERENCES signalbox_architecture.agent_run(id),
  sequence bigint NOT NULL,
  provider text NOT NULL,
  operation_id text NOT NULL,
  input_image text NOT NULL,
  result_image text,
  state text NOT NULL CHECK (state IN ('STARTED', 'SUCCEEDED', 'FAILED', 'TIMED_OUT', 'UNKNOWN')),
  exit_code integer,
  timed_out boolean,
  started_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (run_id, sequence),
  UNIQUE (provider, operation_id),
  CHECK ((state = 'STARTED' AND completed_at IS NULL) OR state <> 'STARTED')
);

CREATE TABLE IF NOT EXISTS signalbox_architecture.run_artifact (
  run_id uuid NOT NULL REFERENCES signalbox_architecture.agent_run(id),
  kind text NOT NULL CHECK (kind IN ('DIFF', 'LOG', 'OTHER')),
  sequence bigint NOT NULL CHECK (sequence > 0),
  artifact_id uuid NOT NULL REFERENCES signalbox_architecture.object_artifact(id),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  PRIMARY KEY (run_id, kind, sequence)
);

-- Governance writes use current kernel roles, never action-approval authority.
CREATE OR REPLACE FUNCTION signalbox_architecture.can_administer_governance(p_org_id uuid, p_principal_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  RETURN EXISTS (
    SELECT 1 FROM model_signalbox.principal
    WHERE id = p_principal_id AND org_id = p_org_id
      AND kind = 'HUMAN' AND status = 'ACTIVE' AND 'ADMIN' = ANY(roles)
  );
END
$signalbox$;

CREATE OR REPLACE FUNCTION signalbox_architecture.assert_governance_admin(p_org_id uuid, p_principal_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  -- Hold permission until commit, serializing concurrent role/status revocation.
  PERFORM 1 FROM model_signalbox.principal
  WHERE id = p_principal_id AND org_id = p_org_id
    AND kind = 'HUMAN' AND status = 'ACTIVE' AND 'ADMIN' = ANY(roles)
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_GOVERNANCE_ADMIN_REQUIRED';
  END IF;
END
$signalbox$;

CREATE OR REPLACE FUNCTION signalbox_architecture.save_compiled_bundle(
  p_id uuid, p_org_id uuid, p_model_name text, p_model_version text,
  p_source_hash text, p_bundle_hash text, p_compiler_version text, p_runtime_compatibility text,
  p_source_artifact_id uuid, p_bundle_artifact_id uuid, p_operation_ids jsonb, p_created_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_id uuid;
BEGIN
  PERFORM signalbox_architecture.assert_governance_admin(p_org_id, p_created_by);
  IF NOT EXISTS (
    SELECT 1 FROM signalbox_architecture.object_artifact
    WHERE id = p_source_artifact_id AND org_id = p_org_id AND kind = 'MODEL_SOURCE' AND sha256 = p_source_hash
  ) OR NOT EXISTS (
    SELECT 1 FROM signalbox_architecture.object_artifact
    WHERE id = p_bundle_artifact_id AND org_id = p_org_id AND kind = 'GOVERNANCE_BUNDLE'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'SB_GOVERNANCE_ARTIFACT_MISMATCH';
  END IF;
  INSERT INTO signalbox_architecture.governance_bundle (
    id, org_id, model_name, model_version, source_hash, bundle_hash, compiler_version,
    runtime_compatibility, source_artifact_id, bundle_artifact_id, operation_ids, status, created_by
  ) VALUES (
    p_id, p_org_id, p_model_name, p_model_version, p_source_hash, p_bundle_hash, p_compiler_version,
    p_runtime_compatibility, p_source_artifact_id, p_bundle_artifact_id, p_operation_ids, 'COMPILED', p_created_by
  )
  ON CONFLICT (org_id, source_hash) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM signalbox_architecture.governance_bundle
    WHERE org_id = p_org_id AND source_hash = p_source_hash AND bundle_hash = p_bundle_hash
      AND compiler_version = p_compiler_version AND runtime_compatibility = p_runtime_compatibility;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'SB_GOVERNANCE_IMMUTABLE_CONFLICT';
    END IF;
  END IF;
  RETURN v_id;
END
$signalbox$;

CREATE OR REPLACE FUNCTION signalbox_architecture.activate_bundle(
  p_org_id uuid, p_bundle_id uuid, p_activated_by uuid, p_bundle_hash text, p_source_hash text
)
RETURNS TABLE (id uuid, previous_bundle_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_candidate signalbox_architecture.governance_bundle%ROWTYPE;
  v_previous_id uuid;
BEGIN
  -- Serialize first activation as well as replacements within one tenant.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org_id::text, 0));
  PERFORM signalbox_architecture.assert_governance_admin(p_org_id, p_activated_by);
  SELECT bundle.* INTO v_candidate FROM signalbox_architecture.governance_bundle AS bundle
  WHERE bundle.org_id = p_org_id AND bundle.id = p_bundle_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'SB_GOVERNANCE_BUNDLE_NOT_FOUND';
  END IF;
  IF v_candidate.bundle_hash IS DISTINCT FROM p_bundle_hash OR v_candidate.source_hash IS DISTINCT FROM p_source_hash THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'SB_GOVERNANCE_ARTIFACT_MISMATCH';
  END IF;
  IF v_candidate.status = 'ACTIVE' THEN
    RETURN QUERY SELECT v_candidate.id, v_candidate.previous_bundle_id;
    RETURN;
  END IF;
  SELECT bundle.id INTO v_previous_id FROM signalbox_architecture.governance_bundle AS bundle
  WHERE bundle.org_id = p_org_id AND bundle.status = 'ACTIVE' FOR UPDATE;
  UPDATE signalbox_architecture.governance_bundle AS bundle SET status = 'RETIRED'
  WHERE bundle.org_id = p_org_id AND bundle.id = v_previous_id;
  UPDATE signalbox_architecture.governance_bundle AS bundle
  SET status = 'ACTIVE', previous_bundle_id = v_previous_id,
      activated_by = p_activated_by, activated_at = pg_catalog.transaction_timestamp()
  WHERE bundle.org_id = p_org_id AND bundle.id = p_bundle_id;
  RETURN QUERY SELECT p_bundle_id, v_previous_id;
END
$signalbox$;

GRANT USAGE ON SCHEMA signalbox_architecture TO modellang_gateway;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA signalbox_architecture TO modellang_gateway;
REVOKE INSERT, UPDATE, DELETE ON signalbox_architecture.governance_bundle FROM modellang_gateway;
REVOKE UPDATE, DELETE ON signalbox_architecture.object_artifact FROM modellang_gateway;
REVOKE ALL ON FUNCTION signalbox_architecture.can_administer_governance(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION signalbox_architecture.assert_governance_admin(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION signalbox_architecture.save_compiled_bundle(uuid, uuid, text, text, text, text, text, text, uuid, uuid, jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION signalbox_architecture.activate_bundle(uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION signalbox_architecture.can_administer_governance(uuid, uuid) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION signalbox_architecture.assert_governance_admin(uuid, uuid) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION signalbox_architecture.save_compiled_bundle(uuid, uuid, text, text, text, text, text, text, uuid, uuid, jsonb, uuid) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION signalbox_architecture.activate_bundle(uuid, uuid, uuid, text, text) TO modellang_gateway;

COMMIT;
