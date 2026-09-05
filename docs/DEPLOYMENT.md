# Hosted deployment

The demo runs at https://143-198-185-50.sslip.io/studio/ with the existing reviewer login. Reviewers can inspect actions and validate policy; only an administrator can compile, activate, or roll back policy.

The API is `signalbox.service`, working in `/opt/signalbox`. The static-site connector is `signalbox-worker.service`. Both are enabled at boot. Caddy terminates HTTPS, proxies the application, and serves `/demo/site/` from `/var/www/signalbox-demo`. The recorded local walkthrough is available at `/demo/recording/signalbox-evidence-walkthrough.mp4`.

## Release procedure

1. Back up the database with `pg_dump -Fc`, the application directory, systemd units, and Caddy configuration. Keep backups private.
2. Build a staged release with `npm ci`, `npm run generated:build`, and `npm run host:build`. Test database upgrades against a restored backup before touching the live database.
3. Stop the API and worker before replacing the application or installing the first policy runtime. Run `scripts/upgrade-policy-runtime.mjs` with `ADMIN_DATABASE_URL` for installation and `DATABASE_URL` for gateway verification. Both must point at the same database. This is separate from the fresh installer; never rerun `seed.sql` on an existing deployment.
4. Configure `SIGNALBOX_POLICY_DATABASE_URL` for a separate policy installer login with permission to SET ROLE `modellang_owner`. Keep it out of agent and worker credentials. Install and activate a compatible bundle through `GovernanceBundleCompiler`, `PostgresPolicyInstaller`, and `ArchitectureRepository`, or an authenticated administrator's Studio session.
5. Start the API and worker. Check authenticated bootstrap, denied production, allowed staging, worker completion, public artifact content, activity evidence, and rejection of reviewer policy publication.

The worker has a separate environment file containing only its gateway connection and worker configuration. Its static-site source is a disposable directory containing only the saved agent-produced HTML. Publication writes to `/var/www/signalbox-demo`; the source repository and credentials are not served.

The September 4 release was verified with a fresh hosted transaction using the previously checked agent artifact. No new inference or Sandbox calls ran during deployment. See [hosted evidence](HOSTED-RELEASE-EVIDENCE.json). The video remains explicitly labeled as a walkthrough of the earlier local run.

## Rollback

The pre-upgrade database dump, application archive, and service/proxy configuration are retained under `/root/signalbox-backups/2026-09-04/`. The prior application directory is `/opt/signalbox-before-64bbba0`. A rollback across the policy-runtime migration requires coordinated database and application restoration while both services are stopped; restoring the old application alone is insufficient. Restoring the database discards post-backup transactions, so retain a fresh dump before choosing that recovery path.
