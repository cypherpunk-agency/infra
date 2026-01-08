# Deployment Guide

This guide is for deploying new services to the infrastructure. It covers what you need to produce and how to configure deployments.

## Target Environment

### Server Details

| Property | Value |
|----------|-------|
| IP Address | `34.67.186.58` |
| SSH Access | `gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap` |
| OS | Ubuntu 24.04 LTS |
| Docker | Docker CE + Compose plugin |

### Directory Structure on Server

```
/mnt/pd/
├── stack/                 # Docker Compose configuration
│   ├── docker-compose.yml # Service definitions
│   └── Caddyfile          # Reverse proxy config
├── data/                  # Persistent application data
│   └── <service-name>/    # Per-service data directories
└── secrets/               # Environment files with secrets
    └── <service-name>.env
```

### How Routing Works

```
Internet → Caddy (:80/:443) → service-name:port
```

Caddy:
- Listens on ports 80 and 443
- Routes by domain name to internal containers
- Automatically provisions TLS via Let's Encrypt
- Containers are on the `web` Docker network

## Requirements for Your Application

### 1. Docker Image

Your application must be packaged as a Docker image.

**Image Registry Options:**
- GitHub Container Registry: `ghcr.io/<org>/<repo>:tag`
- Google Artifact Registry: `us-central1-docker.pkg.dev/<project>/<repo>/<image>:tag`
- Docker Hub: `<user>/<image>:tag`

**Tagging Strategy:**
- `:prod` - Stable tag, updated on each deploy (recommended)
- `:<git-sha>` - Immutable tag for rollbacks

**Dockerfile Requirements:**
- Expose the port your app listens on
- Run as non-root user (recommended)
- Include health check endpoint (recommended)

### 2. GitHub Actions Workflow

Create `.github/workflows/deploy.yml` in your application repository.

### 3. DNS Record

Point your domain to `34.67.186.58`:
```
Type: A
Name: @ (or subdomain)
Value: 34.67.186.58
```

## What You Need to Produce

For each new service deployment, you need:

1. **Dockerfile** in your app repo
2. **GitHub Actions workflow** for CI/CD
3. **Service block** for docker-compose.yml (on server)
4. **Caddyfile entry** for routing (on server)
5. **Environment file** if secrets needed (on server)

## Example: Complete Deployment Setup

### 1. Dockerfile (in your app repo)

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application
COPY . .

# Run as non-root
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D appuser
USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
```

### 2. GitHub Actions Workflow (in your app repo)

Create `.github/workflows/deploy.yml`:

```yaml
name: Build and Deploy

on:
  push:
    branches: [main]

env:
  IMAGE_NAME: ghcr.io/${{ github.repository }}
  SERVICE_NAME: my-app  # Change this

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:prod
            ${{ env.IMAGE_NAME }}:${{ github.sha }}

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Deploy to server
        run: |
          gcloud compute ssh web-server \
            --zone=us-central1-a \
            --tunnel-through-iap \
            --command="cd /mnt/pd/stack && docker compose pull ${{ env.SERVICE_NAME }} && docker compose up -d ${{ env.SERVICE_NAME }}"
```

**Required GitHub Secrets:**
- `GCP_SA_KEY` - Service account JSON key with IAP access

### 3. Service Block (add to docker-compose.yml on server)

SSH to server and edit `/mnt/pd/stack/docker-compose.yml`:

```yaml
services:
  # ... existing services ...

  my-app:
    image: ghcr.io/your-org/your-repo:prod
    container_name: my-app
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    env_file:
      - /mnt/pd/secrets/my-app.env  # Optional
    volumes:
      - /mnt/pd/data/my-app:/app/data  # Optional
    networks:
      - web
    # Optional health check override
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 4. Caddyfile Entry (add to Caddyfile on server)

Edit `/mnt/pd/stack/Caddyfile`:

```
my-app.example.com {
    reverse_proxy my-app:3000
}
```

### 5. Environment File (if needed)

Create `/mnt/pd/secrets/my-app.env`:

```bash
DATABASE_URL=file:/app/data/db.sqlite
API_KEY=your-secret-key
```

Secure it:
```bash
sudo chmod 600 /mnt/pd/secrets/my-app.env
```

### 6. Data Directory (if needed)

```bash
sudo mkdir -p /mnt/pd/data/my-app
sudo chown 1001:1001 /mnt/pd/data/my-app  # Match container user
```

### 7. Deploy

```bash
cd /mnt/pd/stack
docker compose pull my-app
docker compose up -d my-app
```

## Caddyfile Patterns

### Basic reverse proxy
```
example.com {
    reverse_proxy my-app:3000
}
```

### With www redirect
```
example.com {
    reverse_proxy my-app:3000
}

www.example.com {
    redir https://example.com{uri} permanent
}
```

### Path-based routing
```
example.com {
    reverse_proxy /api/* api-service:5000
    reverse_proxy /* frontend:3000
}
```

### With CORS headers
```
api.example.com {
    reverse_proxy api-service:5000

    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Content-Type, Authorization"
}
```

### Static files
```
static.example.com {
    root * /srv/static
    file_server
}
```
(Requires volume mount in Caddy service)

## Deployment Checklist

Use this checklist when deploying a new service:

- [ ] Domain DNS points to `34.67.186.58`
- [ ] Dockerfile exists in app repo
- [ ] GitHub Actions workflow created
- [ ] `GCP_SA_KEY` secret added to repo
- [ ] Service block added to `/mnt/pd/stack/docker-compose.yml`
- [ ] Caddyfile entry added for domain
- [ ] Data directory created (if app needs persistence)
- [ ] Environment file created (if app needs secrets)
- [ ] Initial deploy: `docker compose up -d <service>`
- [ ] Verify: `curl -I https://your-domain.com`

## Updating Existing Services

CI/CD handles this automatically. Manual update:

```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
cd /mnt/pd/stack
docker compose pull my-app
docker compose up -d my-app
```

## Rollback

To rollback to a specific version:

```bash
# Edit docker-compose.yml to pin specific SHA
# image: ghcr.io/org/repo:abc123

docker compose up -d my-app
```

## Removing a Service

1. Remove from `docker-compose.yml`
2. Remove from `Caddyfile`
3. Apply: `docker compose up -d`
4. Clean up: `sudo rm -rf /mnt/pd/data/my-app /mnt/pd/secrets/my-app.env`

## Service Account Setup for CI/CD

To allow GitHub Actions to SSH via IAP, create a service account:

```bash
# Create service account
gcloud iam service-accounts create github-deploy \
  --display-name="GitHub Deploy"

# Grant IAP tunnel access
gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:github-deploy@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/iap.tunnelResourceAccessor"

# Grant compute instance access
gcloud projects add-iam-policy-binding cyberphunk-agency \
  --member="serviceAccount:github-deploy@cyberphunk-agency.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

# Create key
gcloud iam service-accounts keys create github-deploy-key.json \
  --iam-account=github-deploy@cyberphunk-agency.iam.gserviceaccount.com

# Add contents of github-deploy-key.json as GCP_SA_KEY secret in GitHub
```
