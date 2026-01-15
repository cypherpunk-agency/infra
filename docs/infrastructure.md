# Infrastructure

This document describes the GCP infrastructure managed by Terraform.

## Architecture

```
GCP VM
├─ Docker Compose
│  ├─ Caddy (reverse proxy)
│  ├─ Site A
│  └─ Site B
└─ Persistent Disk (/mnt/pd)
   ├─ stack/ (compose, Caddyfile)
   ├─ data/ (SQLite, uploads)
   └─ secrets/
```

Static IP + Firewall (80/443 public, SSH via IAP)

## Specifications

| Component | Value |
|-----------|-------|
| Project | `cyberphunk-agency` |
| Region/Zone | `us-central1-a` |
| VM Name | `web-server` |
| Machine Type | `e2-small` (2 shared vCPU, 2GB RAM) |
| Provisioning | Standard (always-on) |
| Boot Disk | 30GB pd-standard, Ubuntu 24.04 LTS |
| Data Disk | 20GB pd-standard at `/mnt/pd` |
| External IP | `34.67.186.58` (static) |
| SSH | IAP TCP tunneling only |

## Terraform

Managed with Terraform, which invokes `startup-script.sh` on VM boot. See [terraform/README.md](../terraform/README.md).

## Security

- **SSH:** No public access. IAP TCP tunneling only (source: `35.235.240.0/20`)
- **Web:** Ports 80/443 open to `0.0.0.0/0`
- **Shielded VM:** Secure boot, vTPM, integrity monitoring enabled
- **Service Account:** Minimal scopes (storage read, logging, monitoring)

## Deployment System

External teams deploy their containers via GitHub Actions. The system enforces that each team can only deploy their own service.

### Architecture

```
GitHub Actions                         GCP VM
     │                                   │
     │  gcloud ssh (IAP tunnel)          │
     ├──────────────────────────────────►│
     │                                   │
     │  sudo /usr/local/bin/deploy-service SERVICE_NAME
     │                                   │
     │                    ┌──────────────┴──────────────┐
     │                    │      sudoers check          │
     │                    │  user X can only deploy X   │
     │                    └──────────────┬──────────────┘
     │                                   │
     │                    ┌──────────────▼──────────────┐
     │                    │     deploy-service          │
     │                    │  - validate service name    │
     │                    │  - docker compose pull      │
     │                    │  - docker compose up -d     │
     │                    └─────────────────────────────┘
```

### Components

**Service Accounts** (GCP IAM)
- One per external project: `deploy-{service}@cyberphunk-agency.iam.gserviceaccount.com`
- Roles: `iap.tunnelResourceAccessor`, `compute.instanceAdmin.v1`, `iam.serviceAccountUser`
- Key stored as `GCP_SA_KEY` secret in their repo

**Deploy Script** (`/usr/local/bin/deploy-service`)
- Validates service name (alphanumeric, hyphens, underscores)
- Verifies service exists in docker-compose.yml
- Runs `docker compose pull` + `up -d` for that service only

**Access Control** (`/etc/sudoers.d/deploy-{service}`)
- Per-service sudoers rules restrict each SA user to their service
- Example: `deploy-foo ALL=(ALL) NOPASSWD: /usr/local/bin/deploy-service foo`
- User `deploy-foo` can ONLY run `deploy-service foo`, nothing else

### SSH Username Mapping

When a service account SSHs via gcloud, the Linux username is derived from the SA email:
- SA: `deploy-opengov-monitor@cyberphunk-agency.iam.gserviceaccount.com`
- SSH username: `deploy-opengov-monitor`

This predictable mapping allows pre-configuring sudoers rules during onboarding.

### Files on VM

```
/usr/local/bin/deploy-service         # Deploy script (755, root:root)
/etc/sudoers.d/deploy-{service}       # Per-service access rules (440, root:root)
/mnt/pd/stack/docker-compose.yml      # Service definitions
/mnt/pd/stack/Caddyfile               # Reverse proxy config
/mnt/pd/data/{service}/               # Persistent data per service
/mnt/pd/secrets/{service}.env         # Environment secrets per service
```
