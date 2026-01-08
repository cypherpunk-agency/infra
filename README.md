# Infra

Single GCP VM running containerized websites with Docker Compose and Caddy.

## Server

| | |
|---|---|
| **IP** | `34.67.186.58` |
| **SSH** | `gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap` |

## Quick Commands

```bash
# SSH
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# View containers
docker ps

# Logs
cd /mnt/pd/stack && docker compose logs -f

# Redeploy all
cd /mnt/pd/stack && docker compose pull && docker compose up -d

# Start VM if stopped
gcloud compute instances start web-server --zone=us-central1-a
```

## Docs

| Doc | For | Purpose |
|-----|-----|---------|
| [containerization-guide](docs/containerization-guide.md) | App teams | What we need + deploy snippet |
| [adding-services](docs/adding-services.md) | Us | Onboarding checklist |
| [infrastructure](docs/infrastructure.md) | Us | Terraform, architecture |
| [operations](docs/operations.md) | Us | Logs, maintenance |

## Deploying New Services

**App team:**
1. Sends us: image, port, domain, secrets, storage
2. We configure server + give them `GCP_SA_KEY`
3. They add deploy job → push to main → auto-deploys

See [containerization-guide](docs/containerization-guide.md) for app teams, [adding-services](docs/adding-services.md) for us.
