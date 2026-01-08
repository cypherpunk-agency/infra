# Adding Services

Checklist for onboarding a new service.

## Required Info

Get from app team:

| Field | Value |
|-------|-------|
| Image | `ghcr.io/org/repo:prod` |
| Port | |
| Domain | |
| Secrets | |
| Storage | |

## 1. Add to docker-compose.yml

SSH to server:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
```

Edit `/mnt/pd/stack/docker-compose.yml`:

```yaml
  service-name:
    image: ghcr.io/org/repo:prod
    container_name: service-name
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    env_file:
      - /mnt/pd/secrets/service-name.env  # if secrets
    volumes:
      - /mnt/pd/data/service-name:/app/data  # if storage
    networks:
      - web
```

## 2. Add to Caddyfile

Edit `/mnt/pd/stack/Caddyfile`:

```
domain.example.com {
    reverse_proxy service-name:PORT
}
```

## 3. Create Directories/Secrets

If storage needed:
```bash
sudo mkdir -p /mnt/pd/data/service-name
sudo chown 1001:1001 /mnt/pd/data/service-name
```

If secrets needed:
```bash
sudo nano /mnt/pd/secrets/service-name.env
sudo chmod 600 /mnt/pd/secrets/service-name.env
```

## 4. Initial Deploy

```bash
cd /mnt/pd/stack
docker compose pull service-name
docker compose up -d service-name
```

## 5. Create Service Account for Their Repo

Each repo gets its own service account (can revoke individually).

```bash
# Replace SERVICE_NAME with their service name
SERVICE_NAME=their-service

# Create service account
gcloud iam service-accounts create deploy-$SERVICE_NAME \
  --display-name="Deploy $SERVICE_NAME"

# Grant IAP tunnel access
gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor"

# Grant compute access (for SSH)
gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

# Generate key
gcloud iam service-accounts keys create deploy-$SERVICE_NAME-key.json \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com
```

## 6. Add Key to Their Repo

Go to their repo → Settings → Secrets → Actions → New repository secret

- Name: `GCP_SA_KEY`
- Value: Contents of `deploy-$SERVICE_NAME-key.json`

Then delete the local key file:
```bash
rm deploy-$SERVICE_NAME-key.json
```

## 7. Tell Them

- Service name: `service-name`
- Add deploy job from [containerization-guide.md](containerization-guide.md)

---

## Revoking Access

To revoke a repo's deploy access:

```bash
SERVICE_NAME=their-service

# Delete all keys
gcloud iam service-accounts keys list \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com

gcloud iam service-accounts keys delete KEY_ID \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com

# Or delete the whole service account
gcloud iam service-accounts delete deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com
```
