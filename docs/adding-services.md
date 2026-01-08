# Adding Services

## Process Overview

```
App Team                              Us
    │                                  │
    ├─ Send 5 fields ─────────────────►│
    │                                  ├─ Create service account + key
    │                                  ├─ Configure server
    │◄─────────── GCP_SA_KEY + service name
    │                                  │
    ├─ Add deploy job to workflow      │
    ├─ Push to main ──────────────────►│ (auto-deploys)
```

## Required Info

Get from app team:

| Field | Example |
|-------|---------|
| Image | `ghcr.io/org/repo:prod` |
| Port | `3000` |
| Domain | `app.example.com` |
| Secrets | `API_KEY`, `DB_URL` (or none) |
| Storage | `/data` (or none) |

---

## Step 1: Create Service Account + Key

```bash
SERVICE_NAME=their-service

gcloud iam service-accounts create deploy-$SERVICE_NAME \
  --display-name="Deploy $SERVICE_NAME"

gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor" --quiet

gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1" --quiet

gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" --quiet

gcloud iam service-accounts keys create keys/deploy-$SERVICE_NAME-key.json \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com
```

## Step 2: Configure Server

SSH to server:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
```

**Add to docker-compose.yml** (`/mnt/pd/stack/docker-compose.yml`):
```yaml
  service-name:
    image: ghcr.io/org/repo:prod
    container_name: service-name
    restart: unless-stopped
    env_file:
      - /mnt/pd/secrets/service-name.env  # if secrets
    volumes:
      - /mnt/pd/data/service-name:/data  # if storage
    networks:
      - web
```

**Add to Caddyfile** (`/mnt/pd/stack/Caddyfile`):
```
domain.example.com {
    reverse_proxy service-name:PORT
}
```

**Restart Caddy** to apply config and provision TLS certificate:
```bash
cd /mnt/pd/stack && sudo docker compose restart caddy
```

> **Note:** We use `admin off` in Caddyfile for security, so `caddy reload` won't work. Always restart the container.

**Create directories** (if storage needed):
```bash
sudo mkdir -p /mnt/pd/data/service-name
sudo chmod 777 /mnt/pd/data/service-name
```

**Create secrets** (if needed):
```bash
sudo nano /mnt/pd/secrets/service-name.env
sudo chmod 600 /mnt/pd/secrets/service-name.env
```

**Grant service access** (deploy, status, logs, shell - only for their service):
```bash
echo 'deploy-SERVICE_NAME ALL=(ALL) NOPASSWD: /usr/local/bin/deploy-service SERVICE_NAME
deploy-SERVICE_NAME ALL=(ALL) NOPASSWD: /usr/local/bin/service-status SERVICE_NAME
deploy-SERVICE_NAME ALL=(ALL) NOPASSWD: /usr/local/bin/service-logs SERVICE_NAME
deploy-SERVICE_NAME ALL=(ALL) NOPASSWD: /usr/local/bin/service-logs SERVICE_NAME *
deploy-SERVICE_NAME ALL=(ALL) NOPASSWD: /usr/local/bin/service-shell SERVICE_NAME' | sudo tee /etc/sudoers.d/deploy-SERVICE_NAME
sudo chmod 440 /etc/sudoers.d/deploy-SERVICE_NAME
```

## Step 3: Send Key to App Team

Send them:
- The key file (`keys/deploy-$SERVICE_NAME-key.json`)
- Their service name
- Link to [containerization-guide.md](containerization-guide.md)

They will:
- Add the key to GitHub as `GCP_SA_KEY` secret
- Use the key locally for debugging (optional)

Or add the secret directly to their repo:
```bash
gh secret set GCP_SA_KEY --repo org/repo < keys/deploy-$SERVICE_NAME-key.json
```

## Step 4: Verify First Deploy

After they push, verify the container is running and healthy:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo /usr/local/bin/service-status service-name"
```

If unhealthy, check logs:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo /usr/local/bin/service-logs service-name 50"
```

---

## Revoking Access

```bash
SERVICE_NAME=their-service

# Delete service account
gcloud iam service-accounts delete deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com

# Remove sudoers rule from server
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo rm /etc/sudoers.d/deploy-$SERVICE_NAME"
```

## Rotating Keys

If a key is compromised:
```bash
SERVICE_NAME=their-service

# List keys
gcloud iam service-accounts keys list \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com

# Delete old key
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com

# Create new key
gcloud iam service-accounts keys create keys/deploy-$SERVICE_NAME-key.json \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com

# Update their repo secret
gh secret set GCP_SA_KEY --repo org/repo < keys/deploy-$SERVICE_NAME-key.json
```

