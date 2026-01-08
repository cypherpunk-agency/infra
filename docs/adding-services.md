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

## 1. Create Service Account (do this first!)

Create immediately so they can set up their CI workflow while we configure server.

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

gcloud iam service-accounts keys create keys/deploy-$SERVICE_NAME-key.json \
  --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com
```

## 2. Send Them the Key + Instructions

Add key to their repo:
```bash
gh secret set GCP_SA_KEY --repo org/repo < keys/deploy-$SERVICE_NAME-key.json
```

Tell them:
- Service name: `$SERVICE_NAME`
- Add deploy job from [containerization-guide.md](containerization-guide.md)
- **Wait for us to finish server config before pushing**

## 3. Add to docker-compose.yml

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
      - /mnt/pd/data/service-name:/data  # if storage
    networks:
      - web
```

## 4. Add to Caddyfile

Edit `/mnt/pd/stack/Caddyfile`:

```
domain.example.com {
    reverse_proxy service-name:PORT
}
```

## 5. Create Directories/Secrets

If storage needed:
```bash
sudo mkdir -p /mnt/pd/data/service-name
sudo chmod 777 /mnt/pd/data/service-name
```

If secrets needed:
```bash
sudo nano /mnt/pd/secrets/service-name.env
sudo chmod 600 /mnt/pd/secrets/service-name.env
```

## 6. Initial Deploy

```bash
cd /mnt/pd/stack
docker compose pull service-name
docker compose up -d service-name
```

---

## Revoking Access

To revoke a repo's deploy access:

```bash
SERVICE_NAME=their-service
gcloud iam service-accounts delete deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com
```
