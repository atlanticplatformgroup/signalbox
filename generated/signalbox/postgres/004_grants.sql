-- Generated least-privilege application boundary.
REVOKE CREATE ON SCHEMA "model_signalbox" FROM PUBLIC, modellang_app, modellang_gateway, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON SCHEMA "model_signalbox_internal" FROM PUBLIC, modellang_app, modellang_gateway, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
GRANT USAGE ON SCHEMA "model_signalbox" TO modellang_app;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_gateway;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_dispatcher;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_consumer;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_recovery;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_publication_recovery;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_failure_observer;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_failure_acknowledger;
GRANT USAGE ON SCHEMA "model_signalbox_internal" TO modellang_failure_claimant;

REVOKE ALL ON TABLE "model_signalbox"."organization" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."principal" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."agent_credential_metadata" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."connector" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."repository" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."environment" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."delegation" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."allowance" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."issue_request" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."pull_request" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."deployment_request" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."schema_migration_request" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."approval" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON TABLE "model_signalbox"."execution" FROM PUBLIC, modellang_app, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;

REVOKE ALL ON FUNCTION "model_signalbox"."request_issue_creation"(uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."request_issue_creation"(uuid, uuid, uuid, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_ea693a4d658449fbab5741b8369bc276"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_ea693a4d658449fbab5741b8369bc276"(uuid, uuid, uuid, text, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."request_pull_request"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."request_pull_request"(uuid, uuid, uuid, text, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_c4bb8af190dd48efb9784efb9ff9030c"(uuid, uuid, uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_c4bb8af190dd48efb9784efb9ff9030c"(uuid, uuid, uuid, text, text, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."request_staging_deployment"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."request_staging_deployment"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_1388eb9f38684fa0830f60156cdba497"(uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_1388eb9f38684fa0830f60156cdba497"(uuid, uuid, uuid, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."request_production_deployment"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."request_production_deployment"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_d10d1618ed4045f396b64fc3745ce3dd"(uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_d10d1618ed4045f396b64fc3745ce3dd"(uuid, uuid, uuid, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."request_schema_migration"(uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."request_schema_migration"(uuid, uuid, uuid, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_411bfff32560406186bd2d442f1ecf3b"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_411bfff32560406186bd2d442f1ecf3b"(uuid, uuid, uuid, text, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."approve_production_deployment"(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."approve_production_deployment"(uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_047a601f15384b5ea4bfa05b5ef72676"(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_047a601f15384b5ea4bfa05b5ef72676"(uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."reject_production_deployment"(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."reject_production_deployment"(uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_18ab026d358144dfa4d1729e40dd832e"(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_18ab026d358144dfa4d1729e40dd832e"(uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."approve_schema_migration"(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."approve_schema_migration"(uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_4c170dfcb0224cb8aaf078fe6b6ef23d"(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_4c170dfcb0224cb8aaf078fe6b6ef23d"(uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."reject_schema_migration"(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."reject_schema_migration"(uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_d3a1935e42f24e4d84d25bc05ee690ad"(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_d3a1935e42f24e4d84d25bc05ee690ad"(uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_issue_creation"(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."dispatch_issue_creation"(uuid, uuid, uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_cbb72fd307704ab3927aa4bea8112fbf"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_cbb72fd307704ab3927aa4bea8112fbf"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_pull_request"(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."dispatch_pull_request"(uuid, uuid, uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_3e99da927be642efac3d1bee026ef00a"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_3e99da927be642efac3d1bee026ef00a"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_staging_deployment"(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."dispatch_staging_deployment"(uuid, uuid, uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_3e26a4d454634bf3a2058204146d7c45"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_3e26a4d454634bf3a2058204146d7c45"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_approved_deployment"(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."dispatch_approved_deployment"(uuid, uuid, uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_4a9421bfc2e744969b9f73109e6cda54"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_4a9421bfc2e744969b9f73109e6cda54"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."dispatch_approved_schema_migration"(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."dispatch_approved_schema_migration"(uuid, uuid, uuid) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_70d3862584094631aca61e9db664d991"(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_70d3862584094631aca61e9db664d991"(uuid, uuid, uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."complete_execution"(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."complete_execution"(uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_5be24324b68d4c2eb334732b36e1b16c"(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_5be24324b68d4c2eb334732b36e1b16c"(uuid, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."fail_execution"(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."fail_execution"(uuid, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."decide_act_926686163a6544e79d44dea9336d2c88"(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."decide_act_926686163a6544e79d44dea9336d2c88"(uuid, text, text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."my_issue_requests"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."my_issue_requests"(text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."my_pull_requests"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."my_pull_requests"(text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."my_deployment_requests"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."my_deployment_requests"(text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."deployment_approval_inbox"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."deployment_approval_inbox"(text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."my_schema_migration_requests"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."my_schema_migration_requests"(text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."migration_approval_inbox"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."migration_approval_inbox"(text) TO modellang_app;
REVOKE ALL ON FUNCTION "model_signalbox"."my_executions"(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "model_signalbox"."my_executions"(text) TO modellang_app;
REVOKE ALL ON ALL TABLES IN SCHEMA "model_signalbox_internal" FROM PUBLIC, modellang_app, modellang_gateway, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "model_signalbox_internal" FROM PUBLIC, modellang_app, modellang_gateway, modellang_dispatcher, modellang_consumer, modellang_recovery, modellang_publication_recovery, modellang_failure_observer, modellang_failure_acknowledger, modellang_failure_claimant;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."bind_gateway_identity"(text, text) TO modellang_gateway;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."claim_events"(integer, integer) TO modellang_dispatcher;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."ack_event"(uuid, uuid) TO modellang_dispatcher;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."release_event"(uuid, uuid) TO modellang_dispatcher;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."fail_event"(uuid, uuid, text) TO modellang_dispatcher;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."consumer_failure_state"(text, text) TO modellang_consumer;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."record_consumer_failure"(text, text, integer, text) TO modellang_consumer;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."recover_consumer_failure"(text, text, text) TO modellang_recovery;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."recover_event_publication"(uuid, text) TO modellang_publication_recovery;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."observe_terminal_publications"(timestamptz, timestamptz, uuid, integer) TO modellang_failure_observer;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."observe_terminal_consumers"(timestamptz, timestamptz, text, uuid, integer) TO modellang_failure_observer;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."acknowledge_terminal_publication_failure"(uuid, text) TO modellang_failure_acknowledger;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."acknowledge_terminal_consumer_failure"(text, text, text) TO modellang_failure_acknowledger;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."claim_terminal_publication_failure"(uuid) TO modellang_failure_claimant;
GRANT EXECUTE ON FUNCTION "model_signalbox_internal"."claim_terminal_consumer_failure"(text, text) TO modellang_failure_claimant;

ALTER DEFAULT PRIVILEGES FOR ROLE modellang_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE modellang_owner REVOKE ALL ON TABLES FROM PUBLIC;
DO $modellang$
DECLARE
  v_granted_role text;
  v_member_role text;
BEGIN
  FOR v_granted_role, v_member_role IN
    SELECT granted_role.rolname::text, member_role.rolname::text
    FROM (VALUES
      ('modellang_owner', 'modellang_app'),
      ('modellang_owner', 'modellang_gateway'),
      ('modellang_gateway', 'modellang_app'),
      ('modellang_owner', 'modellang_dispatcher'),
      ('modellang_app', 'modellang_dispatcher'),
      ('modellang_gateway', 'modellang_dispatcher'),
      ('modellang_dispatcher', 'modellang_owner'),
      ('modellang_dispatcher', 'modellang_app'),
      ('modellang_dispatcher', 'modellang_gateway'),
      ('modellang_owner', 'modellang_consumer'),
      ('modellang_app', 'modellang_consumer'),
      ('modellang_gateway', 'modellang_consumer'),
      ('modellang_dispatcher', 'modellang_consumer'),
      ('modellang_consumer', 'modellang_owner'),
      ('modellang_consumer', 'modellang_app'),
      ('modellang_consumer', 'modellang_gateway'),
      ('modellang_consumer', 'modellang_dispatcher'),
      ('modellang_owner', 'modellang_recovery'),
      ('modellang_app', 'modellang_recovery'),
      ('modellang_gateway', 'modellang_recovery'),
      ('modellang_dispatcher', 'modellang_recovery'),
      ('modellang_consumer', 'modellang_recovery'),
      ('modellang_recovery', 'modellang_owner'),
      ('modellang_recovery', 'modellang_app'),
      ('modellang_recovery', 'modellang_gateway'),
      ('modellang_recovery', 'modellang_dispatcher'),
      ('modellang_recovery', 'modellang_consumer'),
      ('modellang_owner', 'modellang_publication_recovery'),
      ('modellang_app', 'modellang_publication_recovery'),
      ('modellang_gateway', 'modellang_publication_recovery'),
      ('modellang_dispatcher', 'modellang_publication_recovery'),
      ('modellang_consumer', 'modellang_publication_recovery'),
      ('modellang_recovery', 'modellang_publication_recovery'),
      ('modellang_publication_recovery', 'modellang_owner'),
      ('modellang_publication_recovery', 'modellang_app'),
      ('modellang_publication_recovery', 'modellang_gateway'),
      ('modellang_publication_recovery', 'modellang_dispatcher'),
      ('modellang_publication_recovery', 'modellang_consumer'),
      ('modellang_publication_recovery', 'modellang_recovery'),
      ('modellang_owner', 'modellang_failure_observer'),
      ('modellang_app', 'modellang_failure_observer'),
      ('modellang_gateway', 'modellang_failure_observer'),
      ('modellang_dispatcher', 'modellang_failure_observer'),
      ('modellang_consumer', 'modellang_failure_observer'),
      ('modellang_recovery', 'modellang_failure_observer'),
      ('modellang_publication_recovery', 'modellang_failure_observer'),
      ('modellang_failure_observer', 'modellang_owner'),
      ('modellang_failure_observer', 'modellang_app'),
      ('modellang_failure_observer', 'modellang_gateway'),
      ('modellang_failure_observer', 'modellang_dispatcher'),
      ('modellang_failure_observer', 'modellang_consumer'),
      ('modellang_failure_observer', 'modellang_recovery'),
      ('modellang_failure_observer', 'modellang_publication_recovery'),
      ('modellang_owner', 'modellang_failure_acknowledger'),
      ('modellang_app', 'modellang_failure_acknowledger'),
      ('modellang_gateway', 'modellang_failure_acknowledger'),
      ('modellang_dispatcher', 'modellang_failure_acknowledger'),
      ('modellang_consumer', 'modellang_failure_acknowledger'),
      ('modellang_recovery', 'modellang_failure_acknowledger'),
      ('modellang_publication_recovery', 'modellang_failure_acknowledger'),
      ('modellang_failure_observer', 'modellang_failure_acknowledger'),
      ('modellang_failure_acknowledger', 'modellang_owner'),
      ('modellang_failure_acknowledger', 'modellang_app'),
      ('modellang_failure_acknowledger', 'modellang_gateway'),
      ('modellang_failure_acknowledger', 'modellang_dispatcher'),
      ('modellang_failure_acknowledger', 'modellang_consumer'),
      ('modellang_failure_acknowledger', 'modellang_recovery'),
      ('modellang_failure_acknowledger', 'modellang_publication_recovery'),
      ('modellang_failure_acknowledger', 'modellang_failure_observer'),
      ('modellang_owner', 'modellang_failure_claimant'),
      ('modellang_app', 'modellang_failure_claimant'),
      ('modellang_gateway', 'modellang_failure_claimant'),
      ('modellang_dispatcher', 'modellang_failure_claimant'),
      ('modellang_consumer', 'modellang_failure_claimant'),
      ('modellang_recovery', 'modellang_failure_claimant'),
      ('modellang_publication_recovery', 'modellang_failure_claimant'),
      ('modellang_failure_observer', 'modellang_failure_claimant'),
      ('modellang_failure_acknowledger', 'modellang_failure_claimant'),
      ('modellang_failure_claimant', 'modellang_owner'),
      ('modellang_failure_claimant', 'modellang_app'),
      ('modellang_failure_claimant', 'modellang_gateway'),
      ('modellang_failure_claimant', 'modellang_dispatcher'),
      ('modellang_failure_claimant', 'modellang_consumer'),
      ('modellang_failure_claimant', 'modellang_recovery'),
      ('modellang_failure_claimant', 'modellang_publication_recovery'),
      ('modellang_failure_claimant', 'modellang_failure_observer'),
      ('modellang_failure_claimant', 'modellang_failure_acknowledger')
    ) AS candidate(granted_role, member_role)
    JOIN pg_catalog.pg_roles AS granted_role ON granted_role.rolname = candidate.granted_role
    JOIN pg_catalog.pg_roles AS member_role ON member_role.rolname = candidate.member_role
    JOIN pg_catalog.pg_auth_members AS membership
      ON membership.roleid = granted_role.oid AND membership.member = member_role.oid
  LOOP
    EXECUTE pg_catalog.format('REVOKE %I FROM %I', v_granted_role, v_member_role);
  END LOOP;
END
$modellang$;
GRANT modellang_app TO modellang_gateway;

