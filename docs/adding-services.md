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

## 5. Add GCP_SA_KEY to Their Repo

Go to their repo → Settings → Secrets → Actions → New repository secret

- Name: `GCP_SA_KEY`
- Value: Contents of service account key JSON

Key location: `github-deploy-key.json` (or create new one - see below)

## 6. Tell Them

- Service name: `service-name`
- Add deploy job from [containerization-guide.md](containerization-guide.md)

---

## Service Account Key

If you need to create the service account:

```bash
# Create (one-time)
gcloud iam service-accounts create github-deploy --display-name="GitHub Deploy"

gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:github-deploy@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:github-deploy@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

# Create key
gcloud iam service-accounts keys create github-deploy-key.json \
  --iam-account=github-deploy@cyberphunk-agency.iam.gserviceaccount.com
```
