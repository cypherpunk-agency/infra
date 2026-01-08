# Operations

This document covers day-to-day operations, maintenance, and troubleshooting.

## SSH Access

Connect via IAP tunnel:

```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
```

## Viewing Logs

### Container Logs

```bash
cd /mnt/pd/stack

# All services
docker compose logs -f

# Specific service
docker compose logs -f my-app

# Last 100 lines
docker compose logs --tail=100 my-app

# Since timestamp
docker compose logs --since="2024-01-01T00:00:00" my-app
```

### Startup Script Log

```bash
sudo cat /var/log/startup-script.log
```

### System Journal

```bash
# Docker daemon
sudo journalctl -u docker

# Startup scripts
sudo journalctl -u google-startup-scripts
```

## Container Management

### View Running Containers

```bash
docker ps
```

### Restart a Service

```bash
cd /mnt/pd/stack
docker compose restart my-app
```

### Restart All Services

```bash
cd /mnt/pd/stack
docker compose restart
```

### Stop a Service

```bash
docker compose stop my-app
```

### View Resource Usage

```bash
docker stats
```

## VM Lifecycle

### Spot/Preemptible Behavior

The VM is a Spot instance. GCP may terminate it with 30 seconds notice when capacity is needed. When this happens:

1. VM stops (not deleted)
2. Data on persistent disk (`/mnt/pd`) is preserved
3. VM needs manual restart

### Check VM Status

```bash
gcloud compute instances describe web-server --zone=us-central1-a --format="value(status)"
```

### Start VM

```bash
gcloud compute instances start web-server --zone=us-central1-a
```

### Stop VM

```bash
gcloud compute instances stop web-server --zone=us-central1-a
```

### After VM Restart

The startup script runs automatically and:
- Mounts the persistent disk
- Starts all containers via `docker compose up -d`

No manual intervention needed.

## Disk Management

### Check Disk Usage

```bash
df -h /mnt/pd
```

### Check Docker Disk Usage

```bash
docker system df
```

### Clean Up Docker

```bash
# Remove unused images (safe)
docker image prune -f

# Remove all unused data (more aggressive)
docker system prune -f

# Remove unused volumes (careful - may delete data)
docker volume prune -f
```

## Backups

### Manual SQLite Backup

```bash
# Stop writes (optional but safer)
docker compose stop my-app

# Copy database
cp /mnt/pd/data/my-app/db.sqlite /mnt/pd/data/my-app/db.sqlite.backup

# Restart
docker compose start my-app
```

### Backup to GCS

```bash
# Install gsutil if not present
# Already available on GCP VMs

# Backup data directory
gsutil -m cp -r /mnt/pd/data gs://your-backup-bucket/$(date +%Y%m%d)/
```

### Automated Backups (Cron)

```bash
sudo crontab -e
```

Add:
```
0 3 * * * /usr/bin/gsutil -m cp -r /mnt/pd/data gs://your-backup-bucket/$(date +\%Y\%m\%d)/ >> /var/log/backup.log 2>&1
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs my-app

# Check container status
docker ps -a | grep my-app

# Try starting manually
docker compose up my-app  # Without -d to see output
```

### Can't Pull Image

```bash
# Check if image exists
docker pull ghcr.io/org/repo:prod

# Check authentication
docker login ghcr.io

# On GHCR, ensure package is public or VM has access
```

### Caddy Certificate Issues

```bash
# Check Caddy logs
docker compose logs caddy

# Verify DNS resolves correctly
dig +short your-domain.com

# Test HTTP challenge
curl http://your-domain.com/.well-known/acme-challenge/test
```

### Disk Full

```bash
# Check what's using space
du -sh /mnt/pd/*
du -sh /mnt/pd/data/*

# Clean Docker
docker system prune -af

# Check logs size
du -sh /var/lib/docker/containers/*/*-json.log
```

### Can't SSH via IAP

Verify IAP permissions:
```bash
gcloud projects get-iam-policy cyberphunk-agency \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/iap.tunnelResourceAccessor"
```

Grant access:
```bash
gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="user:your-email@example.com" \
  --role="roles/iap.tunnelResourceAccessor"
```

### VM Won't Start

Check quota:
```bash
gcloud compute regions describe us-central1 --format="value(quotas)"
```

Check for errors:
```bash
gcloud compute operations list --filter="targetLink:web-server" --limit=5
```

### Service Unhealthy

```bash
# Check health status
docker inspect --format='{{.State.Health.Status}}' my-app

# View health check logs
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' my-app
```

## Monitoring

### Basic Health Check

```bash
curl -I https://your-domain.com
```

### Container Health

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Set Up Uptime Monitoring

Use Google Cloud Monitoring to create uptime checks:

1. Go to Cloud Console → Monitoring → Uptime Checks
2. Create check for your domain
3. Configure alerting (email, Slack, etc.)

## Security Updates

### Update System Packages

```bash
sudo apt update && sudo apt upgrade -y
```

### Update Docker Images

```bash
cd /mnt/pd/stack
docker compose pull
docker compose up -d
```

### Reboot VM (if kernel update)

```bash
sudo reboot
```

## Emergency Procedures

### Service Completely Down

1. Check if VM is running:
   ```bash
   gcloud compute instances describe web-server --zone=us-central1-a
   ```

2. Start if stopped:
   ```bash
   gcloud compute instances start web-server --zone=us-central1-a
   ```

3. SSH and check containers:
   ```bash
   gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
   docker ps
   docker compose up -d
   ```

### Rollback Application

```bash
cd /mnt/pd/stack

# Edit docker-compose.yml to use previous SHA tag
# image: ghcr.io/org/repo:previous-sha

docker compose up -d my-app
```

### Restore from Backup

```bash
# Download backup
gsutil cp -r gs://your-backup-bucket/20240101/data/my-app /mnt/pd/data/

# Restart service
docker compose restart my-app
```
