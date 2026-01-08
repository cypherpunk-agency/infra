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
│   ├── containerization-guide.md # For app agents: how to containerize
│   ├── adding-services.md       # For us: how to add services to infra
│   └── operations.md            # Maintenance, logs, troubleshooting
└── terraform/
    ├── main.tf                  # VM, disks, firewall
    ├── variables.tf
    ├── outputs.tf
    └── startup-script.sh        # Bootstrap script
```

## Documentation

| Document | Audience | Description |
|----------|----------|-------------|
| [Containerization Guide](docs/containerization-guide.md) | App agents | How to containerize a project and produce a deploy manifest |
| [Adding Services](docs/adding-services.md) | Infra operators | How to onboard a service given a manifest |
| [Infrastructure](docs/infrastructure.md) | Infra operators | Architecture, Terraform config, costs |
| [Operations](docs/operations.md) | Infra operators | Logs, maintenance, troubleshooting |

## Workflow

**App agent** (working on an application repo):
1. Read [containerization-guide.md](docs/containerization-guide.md)
2. Create Dockerfile and CI workflow
3. Produce `deploy.yaml` manifest

**Infra operator** (adding to this infrastructure):
1. Receive `deploy.yaml` from app agent
2. Follow [adding-services.md](docs/adding-services.md)
3. Deploy and verify

## Managing Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

See [docs/infrastructure.md](docs/infrastructure.md) for details.
