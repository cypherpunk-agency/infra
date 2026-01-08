# Adding Services

This guide is for infrastructure operators adding a new service to the server. You should have received a deployment manifest (`deploy.yaml`) from the application team.

## Prerequisites

- SSH access to the server
- The application's `deploy.yaml` manifest
- Any secret values for the application
- DNS configured (or access to configure it)

## Process Overview

1. Verify the manifest and image
2. Configure DNS
3. Add service to docker-compose.yml
4. Add routing to Caddyfile
5. Create data directories (if needed)
6. Create secrets file (if needed)
7. Deploy and verify

---

## Step 1: Verify Manifest and Image

Review the `deploy.yaml` from the application:

```yaml
service:
  name: my-app
  image: ghcr.io/org/repo:prod
  port: 3000
  health_check: /health

domains:
  - hostname: myapp.example.com

environment:
  public:
    - NODE_ENV=production
  secrets:
    - DATABASE_URL
    - API_KEY

storage:
  - container_path: /app/data
```

Verify the image is pullable:

```bash
docker pull ghcr.io/org/repo:prod
```

If the image is private, ensure the server has access or the image is public.

---

## Step 2: Configure DNS

Ensure the domain points to our server:

```
Type: A
Name: myapp (or @)
Value: 34.67.186.58
```

Verify:
```bash
dig +short myapp.example.com
# Should return: 34.67.186.58
```

---

## Step 3: Add Service to docker-compose.yml

SSH to server:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
```

Edit compose file:
```bash
cd /mnt/pd/stack
nano docker-compose.yml
```

Add the service block based on the manifest:

```yaml
services:
  # ... existing services ...

  my-app:
    image: ghcr.io/org/repo:prod
    container_name: my-app
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    env_file:
      - /mnt/pd/secrets/my-app.env  # Only if secrets needed
    volumes:
      - /mnt/pd/data/my-app:/app/data  # Only if storage needed
    networks:
      - web
    healthcheck:  # Only if health_check specified
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Template Mapping

| Manifest Field | docker-compose |
|----------------|----------------|
| `service.name` | Service name and `container_name` |
| `service.image` | `image` |
| `service.port` | Used in healthcheck and Caddyfile |
| `service.health_check` | `healthcheck.test` URL path |
| `environment.public` | `environment` list |
| `environment.secrets` | `env_file` reference |
| `storage[].container_path` | `volumes` mapping |
| `resources.memory` | `mem_limit` (optional) |

---

## Step 4: Add Routing to Caddyfile

Edit Caddyfile:
```bash
nano Caddyfile
```

Add entry for the domain:

```
myapp.example.com {
    reverse_proxy my-app:3000
}
```

### Common Patterns

**With www redirect:**
```
myapp.example.com {
    reverse_proxy my-app:3000
}

www.myapp.example.com {
    redir https://myapp.example.com{uri} permanent
}
```

**With path prefix:**
```
example.com {
    reverse_proxy /api/* my-api:5000
    reverse_proxy /* my-frontend:3000
}
```

**With CORS headers (if noted in manifest):**
```
api.example.com {
    reverse_proxy my-api:5000

    header Access-Control-Allow-Origin "https://frontend.example.com"
    header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Content-Type, Authorization"
}
```

---

## Step 5: Create Data Directories

If the manifest specifies storage:

```bash
sudo mkdir -p /mnt/pd/data/my-app
sudo chown 1001:1001 /mnt/pd/data/my-app  # Match container user
```

---

## Step 6: Create Secrets File

If the manifest specifies secrets:

```bash
sudo nano /mnt/pd/secrets/my-app.env
```

Add the secret values (obtain from application team securely):

```
DATABASE_URL=file:/app/data/db.sqlite
API_KEY=actual-secret-value-here
```

Secure the file:
```bash
sudo chmod 600 /mnt/pd/secrets/my-app.env
```

---

## Step 7: Deploy and Verify

Pull and start the service:

```bash
cd /mnt/pd/stack
docker compose pull my-app
docker compose up -d my-app
```

Verify container is running:
```bash
docker ps | grep my-app
```

Check logs:
```bash
docker compose logs -f my-app
```

Test the endpoint:
```bash
curl -I https://myapp.example.com
```

Check health (if configured):
```bash
curl https://myapp.example.com/health
```

---

## Checklist

- [ ] Manifest reviewed
- [ ] Image verified pullable
- [ ] DNS configured and propagated
- [ ] Service added to docker-compose.yml
- [ ] Domain added to Caddyfile
- [ ] Data directory created (if needed)
- [ ] Secrets file created (if needed)
- [ ] Service deployed with `docker compose up -d`
- [ ] Container running (`docker ps`)
- [ ] HTTPS working (`curl -I https://...`)
- [ ] Health check passing (if applicable)

---

## Rollback

If something goes wrong:

```bash
# Stop the service
docker compose stop my-app

# Remove from docker-compose.yml and Caddyfile
nano docker-compose.yml
nano Caddyfile

# Restart Caddy to apply config
docker compose restart caddy
```

---

## Updating Existing Services

When an app pushes a new image:

```bash
cd /mnt/pd/stack
docker compose pull my-app
docker compose up -d my-app
```

This pulls the latest `:prod` tag and restarts only that service.

---

## Removing Services

1. Remove from docker-compose.yml
2. Remove from Caddyfile
3. Apply changes:
   ```bash
   docker compose up -d --remove-orphans
   ```
4. Clean up data (optional):
   ```bash
   sudo rm -rf /mnt/pd/data/my-app
   sudo rm -f /mnt/pd/secrets/my-app.env
   ```
