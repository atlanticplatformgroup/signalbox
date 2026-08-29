-- Signalbox Phase 2 credential boundary. Apply after generated ModelLang SQL.

CREATE SCHEMA IF NOT EXISTS model_signalbox_auth AUTHORIZATION modellang_owner;
SET ROLE modellang_owner;
ALTER SCHEMA model_signalbox_auth OWNER TO modellang_owner;
REVOKE ALL ON SCHEMA model_signalbox_auth FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.assert_gateway()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS gateway_role ON gateway_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS login_role ON login_role.oid = membership.member
    WHERE gateway_role.rolname = 'modellang_gateway'
      AND login_role.rolname = session_user
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_GATEWAY_REQUIRED';
  END IF;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.assert_gateway() FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.resolve_bound_identity(
  p_issuer text,
  p_subject text
)
RETURNS TABLE (
  principal_id uuid,
  org_id uuid,
  principal_kind text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  IF p_issuer IS NULL OR pg_catalog.char_length(p_issuer) NOT BETWEEN 1 AND 512
     OR p_subject IS NULL OR pg_catalog.char_length(p_subject) NOT BETWEEN 1 AND 512 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT principal.id, principal.org_id, principal.kind
  FROM model_signalbox_internal.gateway_principal_binding AS binding
  JOIN model_signalbox.principal AS principal ON principal.id = binding.principal_id
  WHERE binding.issuer = p_issuer
    AND binding.subject = p_subject
    AND principal.status = 'ACTIVE';
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.resolve_bound_identity(text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.can_manage_agent(
  p_issuer text,
  p_subject text,
  p_agent_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_allowed boolean;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  SELECT (
    caller.kind = 'HUMAN'
    AND caller.status = 'ACTIVE'
    AND target.kind = 'AGENT'
    AND caller.org_id = target.org_id
    AND ('ADMIN' = ANY(caller.roles) OR target.responsible_owner_id = caller.id)
  )
  INTO v_allowed
  FROM model_signalbox_internal.gateway_principal_binding AS binding
  JOIN model_signalbox.principal AS caller ON caller.id = binding.principal_id
  JOIN model_signalbox.principal AS target ON target.id = p_agent_id
  WHERE binding.issuer = p_issuer
    AND binding.subject = p_subject;
  RETURN COALESCE(v_allowed, false);
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.can_manage_agent(text, text, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.issue_agent_token(
  p_caller_issuer text,
  p_caller_subject text,
  p_agent_id uuid,
  p_label text,
  p_token_hash text,
  p_expires_at timestamptz,
  p_token_issuer text
)
RETURNS TABLE (
  credential_id uuid,
  credential_org_id uuid,
  credential_agent_id uuid,
  credential_label text,
  credential_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_org_id uuid;
  v_status text;
  v_credential_id uuid;
  v_subject text;
  v_bound_principal uuid;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  IF NOT model_signalbox_auth.can_manage_agent(p_caller_issuer, p_caller_subject, p_agent_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:agent_token_manager';
  END IF;
  IF p_label IS NULL OR pg_catalog.char_length(p_label) NOT BETWEEN 1 AND 128
     OR p_token_hash IS NULL OR p_token_hash !~ '^sha256:[0-9a-f]{64}$'
     OR p_token_issuer IS NULL OR pg_catalog.char_length(p_token_issuer) NOT BETWEEN 1 AND 512
     OR (p_expires_at IS NOT NULL AND p_expires_at <= pg_catalog.transaction_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'SB_VALIDATION:agent_token';
  END IF;

  SELECT principal.org_id, principal.status
  INTO v_org_id, v_status
  FROM model_signalbox.principal AS principal
  WHERE principal.id = p_agent_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'SB_NOT_FOUND:agent';
  END IF;
  IF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:agent_inactive';
  END IF;

  INSERT INTO model_signalbox.agent_credential_metadata
    (org_id, agent_id, label, token_hash, expires_at, revoked_at, last_used_at)
  VALUES
    (v_org_id, p_agent_id, p_label, p_token_hash, p_expires_at, NULL, NULL)
  RETURNING id INTO v_credential_id;

  v_subject := 'agent:' || p_agent_id::text;
  INSERT INTO model_signalbox_internal.gateway_principal_binding (issuer, subject, principal_id)
  VALUES (p_token_issuer, v_subject, p_agent_id)
  ON CONFLICT (issuer, subject) DO NOTHING;

  SELECT binding.principal_id
  INTO v_bound_principal
  FROM model_signalbox_internal.gateway_principal_binding AS binding
  WHERE binding.issuer = p_token_issuer AND binding.subject = v_subject;
  IF v_bound_principal IS DISTINCT FROM p_agent_id THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'SB_CONFLICT:agent_identity_binding';
  END IF;

  RETURN QUERY
  SELECT v_credential_id, v_org_id, p_agent_id, p_label, p_expires_at;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.issue_agent_token(text, text, uuid, text, text, timestamptz, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.rotate_agent_token(
  p_caller_issuer text,
  p_caller_subject text,
  p_credential_id uuid,
  p_label text,
  p_token_hash text,
  p_expires_at timestamptz,
  p_token_issuer text
)
RETURNS TABLE (
  credential_id uuid,
  credential_org_id uuid,
  credential_agent_id uuid,
  credential_label text,
  credential_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_old model_signalbox.agent_credential_metadata%ROWTYPE;
  v_agent_status text;
  v_new_credential_id uuid;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  SELECT credential.*
  INTO v_old
  FROM model_signalbox.agent_credential_metadata AS credential
  WHERE credential.id = p_credential_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'SB_NOT_FOUND:agent_token';
  END IF;
  IF NOT model_signalbox_auth.can_manage_agent(p_caller_issuer, p_caller_subject, v_old.agent_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:agent_token_manager';
  END IF;
  IF v_old.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'SB_CONFLICT:agent_token_revoked';
  END IF;
  IF p_label IS NULL OR pg_catalog.char_length(p_label) NOT BETWEEN 1 AND 128
     OR p_token_hash IS NULL OR p_token_hash !~ '^sha256:[0-9a-f]{64}$'
     OR p_token_issuer IS NULL OR pg_catalog.char_length(p_token_issuer) NOT BETWEEN 1 AND 512
     OR (p_expires_at IS NOT NULL AND p_expires_at <= pg_catalog.transaction_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'SB_VALIDATION:agent_token';
  END IF;

  SELECT principal.status
  INTO v_agent_status
  FROM model_signalbox.principal AS principal
  WHERE principal.id = v_old.agent_id
  FOR SHARE;
  IF v_agent_status <> 'ACTIVE' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:agent_inactive';
  END IF;

  UPDATE model_signalbox.agent_credential_metadata AS credential
  SET revoked_at = pg_catalog.transaction_timestamp()
  WHERE credential.id = p_credential_id;

  INSERT INTO model_signalbox.agent_credential_metadata
    (org_id, agent_id, label, token_hash, expires_at, revoked_at, last_used_at)
  VALUES
    (v_old.org_id, v_old.agent_id, p_label, p_token_hash, p_expires_at, NULL, NULL)
  RETURNING id INTO v_new_credential_id;

  RETURN QUERY
  SELECT v_new_credential_id, v_old.org_id, v_old.agent_id, p_label, p_expires_at;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.rotate_agent_token(text, text, uuid, text, text, timestamptz, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.revoke_agent_token(
  p_caller_issuer text,
  p_caller_subject text,
  p_credential_id uuid
)
RETURNS TABLE (
  credential_id uuid,
  credential_agent_id uuid,
  credential_revoked_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
DECLARE
  v_credential model_signalbox.agent_credential_metadata%ROWTYPE;
  v_revoked_at timestamptz;
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  SELECT credential.*
  INTO v_credential
  FROM model_signalbox.agent_credential_metadata AS credential
  WHERE credential.id = p_credential_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'SB_NOT_FOUND:agent_token';
  END IF;
  IF NOT model_signalbox_auth.can_manage_agent(p_caller_issuer, p_caller_subject, v_credential.agent_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'SB_AUTHORIZATION:agent_token_manager';
  END IF;

  v_revoked_at := COALESCE(v_credential.revoked_at, pg_catalog.transaction_timestamp());
  UPDATE model_signalbox.agent_credential_metadata AS credential
  SET revoked_at = v_revoked_at
  WHERE credential.id = p_credential_id;

  RETURN QUERY
  SELECT p_credential_id, v_credential.agent_id, v_revoked_at;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.revoke_agent_token(text, text, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION model_signalbox_auth.verify_agent_token(
  p_credential_id uuid,
  p_token_hash text,
  p_token_issuer text
)
RETURNS TABLE (
  identity_issuer text,
  identity_subject text,
  principal_id uuid,
  org_id uuid,
  credential_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $signalbox$
BEGIN
  PERFORM model_signalbox_auth.assert_gateway();
  IF p_token_hash IS NULL OR p_token_hash !~ '^sha256:[0-9a-f]{64}$'
     OR p_token_issuer IS NULL OR pg_catalog.char_length(p_token_issuer) NOT BETWEEN 1 AND 512 THEN
    RETURN;
  END IF;

  RETURN QUERY
  UPDATE model_signalbox.agent_credential_metadata AS credential
  SET last_used_at = pg_catalog.transaction_timestamp()
  FROM model_signalbox.principal AS principal
  WHERE credential.id = p_credential_id
    AND credential.agent_id = principal.id
    AND credential.org_id = principal.org_id
    AND credential.token_hash = p_token_hash
    AND credential.revoked_at IS NULL
    AND (credential.expires_at IS NULL OR credential.expires_at > pg_catalog.transaction_timestamp())
    AND principal.kind = 'AGENT'
    AND principal.status = 'ACTIVE'
    AND EXISTS (
      SELECT 1
      FROM model_signalbox_internal.gateway_principal_binding AS binding
      WHERE binding.issuer = p_token_issuer
        AND binding.subject = 'agent:' || principal.id::text
        AND binding.principal_id = principal.id
    )
  RETURNING p_token_issuer, 'agent:' || principal.id::text, principal.id, principal.org_id, credential.expires_at;
END
$signalbox$;
REVOKE ALL ON FUNCTION model_signalbox_auth.verify_agent_token(uuid, text, text) FROM PUBLIC;

GRANT USAGE ON SCHEMA model_signalbox_auth TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_auth.resolve_bound_identity(text, text) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_auth.issue_agent_token(text, text, uuid, text, text, timestamptz, text) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_auth.rotate_agent_token(text, text, uuid, text, text, timestamptz, text) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_auth.revoke_agent_token(text, text, uuid) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION model_signalbox_auth.verify_agent_token(uuid, text, text) TO modellang_gateway;

RESET ROLE;
