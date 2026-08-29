-- Signalbox spike seed. Runs as the installing role, assuming modellang_owner.
SET ROLE modellang_owner;

DELETE FROM model_signalbox_internal.gateway_principal_binding;
DELETE FROM model_signalbox.execution;
DELETE FROM model_signalbox.approval;
DELETE FROM model_signalbox.production_deploy_request;
DELETE FROM model_signalbox.allowance;
DELETE FROM model_signalbox.delegation;
DELETE FROM model_signalbox.environment;
DELETE FROM model_signalbox.principal;
DELETE FROM model_signalbox.organization;

INSERT INTO model_signalbox.organization (id, slug, name) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'acme',  'Acme Corp'),
  ('00000000-0000-0000-0000-0000000000a2', 'other', 'Other Corp');

-- Acme: one agent, two approvers, one admin. Other Corp: one approver (tenant probe).
INSERT INTO model_signalbox.principal (id, org_id, kind, display_name, status, roles) VALUES
  ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','AGENT','Pi Release Agent','ACTIVE','{MEMBER}'),
  ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a1','HUMAN','Dana Approver','ACTIVE','{MEMBER,APPROVER}'),
  ('00000000-0000-0000-0000-0000000000b3','00000000-0000-0000-0000-0000000000a1','HUMAN','Raj Approver','ACTIVE','{MEMBER,APPROVER}'),
  ('00000000-0000-0000-0000-0000000000b4','00000000-0000-0000-0000-0000000000a1','HUMAN','Ops Admin','ACTIVE','{MEMBER,APPROVER,ADMIN}'),
  ('00000000-0000-0000-0000-0000000000b5','00000000-0000-0000-0000-0000000000a2','HUMAN','Outsider','ACTIVE','{MEMBER,APPROVER}');

INSERT INTO model_signalbox.environment (id, org_id, name, tier) VALUES
  ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000a1','acme-prod','PRODUCTION'),
  ('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000a1','acme-staging','STAGING');

INSERT INTO model_signalbox.delegation (id, org_id, agent_id, capability, environment_id, status) VALUES
  ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000b1','REQUEST_PRODUCTION_DEPLOY','00000000-0000-0000-0000-0000000000c1','ACTIVE');

-- Exactly two allowance tokens for the period. Third execution must be impossible.
INSERT INTO model_signalbox.allowance (id, org_id, period, sequence) VALUES
  ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000a1','2026-10',1),
  ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000a1','2026-10',2);

INSERT INTO model_signalbox_internal.gateway_principal_binding (issuer, subject, principal_id) VALUES
  ('https://signalbox.test','agent:pi',       '00000000-0000-0000-0000-0000000000b1'),
  ('https://signalbox.test','human:dana',     '00000000-0000-0000-0000-0000000000b2'),
  ('https://signalbox.test','human:raj',      '00000000-0000-0000-0000-0000000000b3'),
  ('https://signalbox.test','human:opsadmin', '00000000-0000-0000-0000-0000000000b4'),
  ('https://signalbox.test','human:outsider', '00000000-0000-0000-0000-0000000000b5');

RESET ROLE;
