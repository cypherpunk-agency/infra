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
- **Path**: `/mnt/pd/data/static/`
- **Domains**: cypherpunk.agency, www.cypherpunk.agency
- **Added**: 2025-01 (estimated)
- **Notes**: Serves static HTML/CSS/JS directly from Caddy without a container

---

## Maintenance Notes

### Updating This Document

This document should be updated whenever:
- A new service is added
- A service is removed or decommissioned
- Service configuration changes (domain, image, storage)
- Service accounts are rotated