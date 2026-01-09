# Infrastructure

This document describes the GCP infrastructure managed by Terraform.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Google Cloud Platform                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                   Compute Engine VM                    │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Docker Compose Stack               │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐        │  │  │
│  │  │  │  Caddy  │  │ Site A  │  │ Site B  │  ...   │  │  │
│  │  │  │ (proxy) │  │         │  │         │        │  │  │
│  │  │  └────┬────┘  └─────────┘  └─────────┘        │  │  │
│  │  │       │              ▲           ▲             │  │  │
│  │  │       └──────────────┴───────────┘             │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                         │                              │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │           Persistent Disk (/mnt/pd)             │  │  │
│  │  │   /stack (compose files)                        │  │  │
│  │  │   /data  (SQLite, uploads)                      │  │  │
│  │  │   /secrets                                      │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
│                            │                                 │
│                     Static IP + Firewall                     │
│                     (80, 443 public / 22 via IAP)           │
└─────────────────────────────────────────────────────────────┘
```

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

## Terraform Files

```
terraform/
├── main.tf            # VM, disks, IP, firewall rules
├── variables.tf       # Configurable parameters
├── outputs.tf         # Outputs (IP, SSH command)
├── startup-script.sh  # Bootstrap script (Docker, disk mount)
└── .terraform.lock.hcl
```

### main.tf

Defines:
- `google_compute_address.static_ip` - Static external IP
- `google_compute_disk.data_disk` - Persistent data disk (20GB)
- `google_compute_instance.vm` - The VM instance
- `google_compute_firewall.allow_http_https` - Ports 80/443 from anywhere
- `google_compute_firewall.allow_ssh_iap` - Port 22 from IAP range only

### variables.tf

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | `cyberphunk-agency` | GCP project |
| `region` | `us-central1` | GCP region |
| `zone` | `us-central1-a` | GCP zone |
| `vm_name` | `web-server` | Instance name |
| `machine_type` | `e2-small` | Machine type |
| `disk_size_gb` | `20` | Data disk size |

### startup-script.sh

Runs on every boot (idempotent):
1. Installs Docker + Compose if not present
2. Mounts data disk at `/mnt/pd`
3. Creates directory structure (`/mnt/pd/{stack,data,secrets}`)
4. Creates initial Caddy stack if not present
5. Starts containers with `docker compose up -d`

## Modifying Infrastructure

```bash
cd terraform

# Preview changes
terraform plan

# Apply changes
terraform apply
```

### Common Changes

**Change machine type:**
Edit `variables.tf` or override:
```bash
terraform apply -var="machine_type=e2-medium"
```

**Increase disk size:**
Edit `variables.tf`, then apply. Note: disk can only grow, not shrink.

**Add firewall rules:**
Add new `google_compute_firewall` resource in `main.tf`.

## Cost Estimate

With standard (on-demand) pricing in us-central1:

| Resource | Monthly Cost |
|----------|--------------|
| e2-small (standard) | ~$13 |
| 30GB boot disk | ~$1.20 |
| 20GB data disk | ~$0.80 |
| Static IP (in use) | Free |
| **Total** | **~$15** |

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
