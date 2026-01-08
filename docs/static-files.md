# Hosting Static Files

For simple static sites (HTML/CSS/JS), serve directly from Caddy without a container.

## Setup

1. Copy files to VM:
```bash
# From local machine
gcloud compute scp static/index.html web-server:/tmp/index.html \
  --zone=us-central1-a --tunnel-through-iap

# On VM: move to static directory
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
sudo mkdir -p /mnt/pd/data/static
sudo mv /tmp/index.html /mnt/pd/data/static/
sudo chown -R root:root /mnt/pd/data/static
```

2. Add to Caddyfile (`/mnt/pd/stack/Caddyfile`):
```
cypherpunk.agency {
    root * /static
    file_server
}
```

3. Mount static directory in Caddy (add to `docker-compose.yml`):
```yaml
caddy:
  volumes:
    - /mnt/pd/data/static:/static:ro  # Add this line
```

4. Restart Caddy:
```bash
cd /mnt/pd/stack && sudo docker compose restart caddy
```

## Updating Static Files

```bash
# Copy new file
gcloud compute scp static/index.html web-server:/tmp/index.html \
  --zone=us-central1-a --tunnel-through-iap

# Move into place
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo mv /tmp/index.html /mnt/pd/data/static/"
```

No Caddy restart needed for file updates.

## Notes

- Static files in this repo (`static/`) must be manually copied to the VM
- The `terraform/startup-script.sh` contains the default Caddyfile and docker-compose.yml templates for fresh VMs - update it when adding new permanent patterns
- Current setup serves `cypherpunk.agency` from `/mnt/pd/data/static/`
