# Deployed Services

This document serves as the source of truth for all services currently deployed on our infrastructure. It tracks service configurations, domains, access controls, and deployment details.

## Services

### opengov-monitor
- **Domain**: polkadot-treasury-monitor.cypherpunk.agency
- **Image**: ghcr.io/opengov-watch/opengov-monitor:prod
- **Port**: 80 (internal to container)
- **Service Account**: deploy-opengov-monitor@cyberphunk-agency.iam.gserviceaccount.com
- **Key File**: keys/deploy-opengov-monitor-key.json
- **Persistent Storage**: `/mnt/pd/data/opengov-monitor/` (bind mount)
- **Secrets**: None
- **Notes**:
  - Currently single deployment serving production traffic
  - **Pending migration**: Will be split into `opengov-monitor-dev` and `opengov-monitor-prod`
  - See `docs/opengov-migration-plan.md` for migration details
  - Data is already using bind mount (not Docker volume)

---

## Static Sites

### cypherpunk.agency
- **Type**: Static files (Caddy file_server)
- **Path**: `/mnt/pd/data/services/static/`
- **Domains**: cypherpunk.agency, www.cypherpunk.agency
- **Added**: 2025-01 (estimated)
- **Notes**: Serves static HTML/CSS/JS directly from Caddy without a container

---

### devbox
- **Domain**: code.cypherpunk.agency
- **Image**: ghcr.io/cypherpunk-agency/infra-devbox:latest
- **Ports**: 8443 (code-server web IDE), 2222 (SSH)
- **Service Account**: deploy-devbox@cyberphunk-agency.iam.gserviceaccount.com
- **Key File**: keys/deploy-devbox-key.json
- **Persistent Storage**: `/mnt/pd/data/services/devbox/` (bind mount)
  - `workspace/` - Development files and projects
  - `sites/` - Static websites (can be served via Caddy)
  - `.ssh/` - SSH keys for git operations
  - `.config/` - Tool configurations (code-server, etc.)
- **Secrets**: DEVBOX_PASSWORD (used for both web IDE and SSH access)
- **Tools**: Node.js 22, Python 3.12, Git, gh CLI, vim, nano, curl, htop
- **Access Methods**:
  - Web IDE: https://code.cypherpunk.agency (password-protected)
  - SSH via service-shell: `gcloud compute ssh web-server ... sudo service-shell devbox`
  - Direct SSH: Port 2222 via IAP tunnel (for VS Code Remote SSH)
- **Added**: 2026-01
- **Notes**:
  - Remote development environment for Claude Code and general development
  - Password authentication for both web IDE and SSH
  - Sites in `sites/` subdirectory can be served via Caddy with additional Caddyfile configuration

---

## Maintenance Notes

### Updating This Document

This document should be updated whenever:
- A new service is added
- A service is removed or decommissioned
- Service configuration changes (domain, image, storage)
- Service accounts are rotated