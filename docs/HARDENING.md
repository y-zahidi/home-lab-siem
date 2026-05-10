# Hardening checklist

The default `docker-compose.yml` is set up for **easy local exploration**, not production. Before you put this anywhere on the open internet, walk through this checklist.

## Critical (do these before exposing the dashboard)

- [ ] **Change all default passwords.**
  Edit `docker-compose.yml`:
  - `INDEXER_PASSWORD: SecretPassword`
  - `API_PASSWORD: MyS3cr37P450r.*-`
  - `DASHBOARD_PASSWORD: kibanaserver`
  Use long, unique values. Store them in a secret manager (1Password, Bitwarden, Vault).

- [ ] **Replace self-signed certs with real ones.**
  Wazuh tolerates self-signed in dev. Production needs certs from a trusted CA (Let's Encrypt is fine if the dashboard is internet-facing; an internal CA otherwise).

- [ ] **Put the dashboard behind a reverse proxy** (nginx / Traefik / Caddy) with:
  - HTTP/2 + TLS 1.2+
  - HSTS header
  - IP-based access control (only allow your office / VPN ranges)
  - Optional: SSO (OIDC) integration so you don't manage local users

- [ ] **Restrict the management ports.**
  Ports 1514, 1515, 55000, 9200 should *never* be reachable from the internet. Bind them to internal interfaces only.

## Strongly recommended

- [ ] **Enable Wazuh API audit logs** so every config change is recorded.
- [ ] **Set a retention policy** on the indexer. Default = forever. Use ISM (Index State Management) policies to roll over indices weekly and delete after 90 days (adjust for your compliance needs).
- [ ] **Schedule daily snapshots** of the indexer to S3/MinIO.
- [ ] **Tune resource limits.** Set `OPENSEARCH_JAVA_OPTS` to ~50% of available RAM, capped at 31 GB.
- [ ] **Add health checks.** Use Wazuh's built-in `/api/manager/status` endpoint with Uptime Kuma or similar.

## Nice to have

- [ ] Integrate with VirusTotal (`/var/ossec/integrations/virustotal`) for hash enrichment.
- [ ] Enable Active Response in **audit mode** for at least 2 weeks before going live.
- [ ] Add MISP integration for threat-intel feed correlation.
- [ ] Send critical alerts to a chat channel (Slack/Teams/Mattermost) via the integration framework.

## What to skip (common bad advice)

- ❌ Don't disable cert verification on the manager-to-indexer link "to make it work". Fix the cert chain instead.
- ❌ Don't run the indexer with `discovery.type=single-node` in production. Cluster it.
- ❌ Don't expose the indexer port (9200) to the dashboard's network bridge only — it should be on its own internal-only network.
