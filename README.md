# Server Setup

Infrastructure-as-code for a single GCP Compute Engine VM running multiple containerized websites via Docker Compose.

## Architecture Overview

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

## Current Deployment

| Resource | Value |
|----------|-------|
| VM Name | `web-server` |
| External IP | `34.67.186.58` |
| Zone | `us-central1-a` |
| Status | Live |

**Quick Access:**
- Web: http://34.67.186.58
- SSH: `gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap`

## Infrastructure Specs

| Component | Specification |
|-----------|---------------|
| Project | `cyberphunk-agency` |
| Region/Zone | `us-central1-a` |
| Machine Type | `e2-small` (2 shared vCPU, 2GB RAM) |
| Provisioning | Spot/Preemptible (cost savings) |
| Boot Disk | 30GB pd-standard, Ubuntu 24.04 LTS |
| Data Disk | 20GB pd-standard, mounted at `/mnt/pd` |
| Network | Static external IP (`34.67.186.58`), default VPC |
| SSH Access | IAP TCP tunneling only (no public SSH) |

## Prerequisites

### Required Tools

1. **Google Cloud CLI**
   - Download: https://cloud.google.com/sdk/docs/install
   - Verify: `gcloud version`

2. **Terraform**
   - Install via winget: `winget install HashiCorp.Terraform`
   - Or download: https://developer.hashicorp.com/terraform/downloads
   - Verify: `terraform version`

### GCP Setup

1. **Authenticate with GCP:**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Set the project:**
   ```bash
   gcloud config set project cyberphunk-agency
   ```

3. **Enable required APIs** (already done, but for reference):
   ```bash
   gcloud services enable compute.googleapis.com --project=cyberphunk-agency
   gcloud services enable iap.googleapis.com --project=cyberphunk-agency
   ```

## Deployment

### Initial Deployment

1. **Navigate to terraform directory:**
   ```bash
   cd terraform
   ```

2. **Initialize Terraform:**
   ```bash
   terraform init
   ```

3. **Preview changes:**
   ```bash
   terraform plan
   ```

4. **Apply configuration:**
   ```bash
   terraform apply
   ```

5. **Note the outputs** (static IP, SSH command, etc.)

### Connecting to the VM

SSH via IAP tunnel (secure, no public SSH port):
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
```

### Verifying the Setup

After deployment, the startup script will:
1. Install Docker and Docker Compose
2. Mount the persistent disk at `/mnt/pd`
3. Create initial Caddy stack
4. Start the containers

Check startup script logs:
```bash
sudo cat /var/log/startup-script.log
```

Check running containers:
```bash
docker ps
```

Test the web server (from your local machine):
```bash
curl http://34.67.186.58
```

## Directory Structure

```
server-setup/
├── README.md              # This file
├── SPEC.md                # Detailed specification document
└── terraform/
    ├── main.tf            # Main infrastructure (VM, disk, IP, firewall)
    ├── variables.tf       # Input variables
    ├── outputs.tf         # Output values
    ├── startup-script.sh  # VM bootstrap script
    ├── .terraform/        # Terraform providers (gitignored)
    └── .terraform.lock.hcl # Provider lock file
```

### On the VM (`/mnt/pd/`)

```
/mnt/pd/
├── stack/                 # Docker Compose stack
│   ├── docker-compose.yml
│   └── Caddyfile
├── data/                  # Application data (SQLite, uploads)
│   └── <service>/
└── secrets/               # Sensitive configuration
```

## Maintenance

### Updating Infrastructure

1. Modify Terraform files as needed
2. Preview: `terraform plan`
3. Apply: `terraform apply`

### Restarting the VM

The VM is preemptible/spot, so GCP may stop it. To restart:
```bash
gcloud compute instances start web-server --zone=us-central1-a
```

The startup script is idempotent and will re-run on boot, ensuring Docker and the stack are running.

### Updating the Docker Stack

SSH into the VM and:
```bash
cd /mnt/pd/stack
# Edit docker-compose.yml or Caddyfile as needed
docker compose pull
docker compose up -d
```

### Viewing Logs

Container logs:
```bash
docker compose logs -f           # All services
docker compose logs -f caddy     # Specific service
```

Startup script log:
```bash
sudo cat /var/log/startup-script.log
```

### Checking Disk Usage

```bash
df -h /mnt/pd
```

## Destroying Infrastructure

To tear down all resources:
```bash
cd terraform
terraform destroy
```

**Warning:** This will delete the VM and data disk. Back up `/mnt/pd/data` first if needed.

## Security Notes

- **SSH:** Only accessible via IAP TCP tunneling (no public port 22)
- **Web traffic:** Ports 80/443 open to public (required for web serving)
- **Secrets:** Store in `/mnt/pd/secrets` with restrictive permissions, or use Google Secret Manager
- **Containers:** Only Caddy is exposed; other services communicate via internal Docker network

## Cost Estimate

With Spot/preemptible pricing in us-central1:
- e2-small: ~$3-5/month (spot)
- 30GB boot disk: ~$1.20/month
- 20GB data disk: ~$0.80/month
- Static IP (in use): Free
- **Total:** ~$5-7/month

## Troubleshooting

### VM won't start
Check if you have quota available:
```bash
gcloud compute regions describe us-central1 --format="value(quotas)"
```

### Can't SSH via IAP
Ensure you have the IAP-secured Tunnel User role:
```bash
gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="user:YOUR_EMAIL" \
  --role="roles/iap.tunnelResourceAccessor"
```

### Docker not running after boot
Check startup script logs:
```bash
sudo journalctl -u google-startup-scripts
sudo cat /var/log/startup-script.log
```

### Disk not mounted
Manually mount and check fstab:
```bash
sudo mount -a
cat /etc/fstab
```

## Next Steps

- [x] Initial VM deployment
- [x] Docker + Caddy running
- [ ] Add application containers to the stack
- [ ] Configure domains in Caddyfile for automatic TLS
- [ ] Set up CI/CD for automated deployments
- [ ] Configure backups for `/mnt/pd/data`
- [ ] Add monitoring/alerting
