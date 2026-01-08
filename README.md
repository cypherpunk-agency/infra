# Infra

Infrastructure-as-code for hosting containerized websites on a single GCP Compute Engine VM with Docker Compose and Caddy reverse proxy.

## Current Deployment

| | |
|---|---|
| **IP** | `34.67.186.58` |
| **SSH** | `gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap` |
| **Project** | `cyberphunk-agency` |

## Quick Commands

```bash
# SSH to server
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# View containers
docker ps

# View logs
cd /mnt/pd/stack && docker compose logs -f

# Update stack
cd /mnt/pd/stack && docker compose pull && docker compose up -d

# Start VM (if stopped)
gcloud compute instances start web-server --zone=us-central1-a
```

## Project Structure

```
├── README.md
├── SPEC.md                      # Original design specification
├── docs/
│   ├── infrastructure.md        # Terraform setup, architecture, costs
│   ├── deployment-guide.md      # How to deploy new services
│   └── operations.md            # Maintenance, logs, troubleshooting
└── terraform/
    ├── main.tf                  # VM, disks, firewall
    ├── variables.tf
    ├── outputs.tf
    └── startup-script.sh        # Bootstrap script
```

## Documentation

| Document | Description |
|----------|-------------|
| [Infrastructure](docs/infrastructure.md) | Architecture, Terraform config, costs |
| [Deployment Guide](docs/deployment-guide.md) | How to deploy new services (for agents) |
| [Operations](docs/operations.md) | Logs, maintenance, troubleshooting |

## Deploying New Services

See [docs/deployment-guide.md](docs/deployment-guide.md) for complete instructions.

**Summary:**
1. Create Dockerfile in your app repo
2. Add GitHub Actions workflow for CI/CD
3. Add service to `/mnt/pd/stack/docker-compose.yml` on server
4. Add domain to `/mnt/pd/stack/Caddyfile` on server
5. Deploy: `docker compose up -d`

## Managing Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

See [docs/infrastructure.md](docs/infrastructure.md) for details.
