# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Infrastructure-as-code for a single GCP VM hosting multiple containerized websites with Docker Compose and Caddy reverse proxy. External teams deploy their apps via GitHub Actions.

## Commands

```bash
# Terraform
cd terraform && terraform plan
cd terraform && terraform apply

# SSH to VM
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# On VM: view containers and logs
docker ps
cd /mnt/pd/stack && docker compose logs -f SERVICE_NAME

# On VM: redeploy all services
cd /mnt/pd/stack && docker compose pull && docker compose up -d
```

## Architecture

**GCP Resources** (Terraform-managed in `terraform/`):
- Compute Engine VM (`e2-small`, spot/preemptible, Ubuntu 24.04)
- 20GB persistent disk mounted at `/mnt/pd`
- Static IP, IAP-only SSH (no public port 22)

**VM Directory Structure** (`/mnt/pd/`):
- `stack/` - docker-compose.yml, Caddyfile
- `data/{service}/` - persistent storage per service
- `secrets/{service}.env` - environment files

**Deployment Flow**:
1. External team pushes to their repo → GitHub Actions builds image → pushes to ghcr.io
2. GitHub Actions SSHs via IAP → runs `sudo /usr/local/bin/deploy-service SERVICE_NAME`
3. Deploy script validates service name, pulls image, restarts container

**Access Control**:
- Each external team gets a GCP service account (`deploy-{service}@...`)
- Per-service sudoers rules restrict each SA to deploy only their service
- SSH username derived from SA email (e.g., `deploy-opengov-monitor`)

## Key Files

| File | Purpose |
|------|---------|
| `terraform/main.tf` | VM, disk, IP, firewall rules |
| `terraform/startup-script.sh` | Bootstrap: Docker install, disk mount, deploy script |
| `docs/adding-services.md` | Onboarding checklist for operators |
| `docs/containerization-guide.md` | Instructions for external app teams |
| `keys/` | Service account keys (gitignored) |
