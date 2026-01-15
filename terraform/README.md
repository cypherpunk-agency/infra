# Terraform Setup

Infrastructure-as-code for the GCP VM using Terraform.

## Files

```
terraform/
├── main.tf            # VM, disks, IP, firewall rules
├── variables.tf       # Configurable parameters
├── outputs.tf         # Outputs (IP, SSH command)
├── startup-script.sh  # Bootstrap script (invoked on VM boot)
└── .terraform.lock.hcl
```

## main.tf

Defines:
- `google_compute_address.static_ip` - Static external IP
- `google_compute_disk.data_disk` - Persistent data disk (20GB)
- `google_compute_instance.vm` - The VM instance
- `google_compute_firewall.allow_http_https` - Ports 80/443 from anywhere
- `google_compute_firewall.allow_ssh_iap` - Port 22 from IAP range only

## variables.tf

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | `cyberphunk-agency` | GCP project |
| `region` | `us-central1` | GCP region |
| `zone` | `us-central1-a` | GCP zone |
| `vm_name` | `web-server` | Instance name |
| `machine_type` | `e2-small` | Machine type |
| `disk_size_gb` | `20` | Data disk size |

## startup-script.sh

Runs on every VM boot (idempotent):
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

## When to Use Terraform vs SSH

**Use Terraform** (`terraform apply`) for:
- GCP infrastructure changes (VM size, disk, firewall rules, IAM)
- Changes to `terraform/main.tf` or `terraform/variables.tf`

**Use SSH** for:
- Adding/updating services in docker-compose.yml
- Updating Caddyfile (domains, routes)
- Deploying static files
- Creating secrets or data directories

**Update `terraform/startup-script.sh`** when:
- Adding new patterns that should be set up on fresh VMs
- The startup script is a template for new VMs, not for updating existing ones
- Changes to startup-script.sh don't affect the running VM unless you recreate it
