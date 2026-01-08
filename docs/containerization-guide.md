# Containerization Guide

This guide is for agents working on application repositories. It explains how to containerize your project so it can be deployed to our infrastructure.

**You do not need access to the infrastructure.** Your job is to:
1. Containerize the application
2. Set up CI to build and push images
3. Produce a deployment manifest with the information we need

## What You Need to Produce

### 1. Dockerfile

Create a `Dockerfile` in your repository root that packages your application.

### 2. GitHub Actions Workflow

Create `.github/workflows/build.yml` that builds and pushes your Docker image.

### 3. Deployment Manifest

Create `deploy.yaml` in your repository with the information we need to deploy your service.

---

## Step 1: Create a Dockerfile

### Requirements

- Expose the port your app listens on
- Run as non-root user (recommended)
- Include a health check endpoint if possible

### Examples

**Node.js:**
```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

RUN addgroup -g 1001 -S app && adduser -u 1001 -S app -G app
USER app

EXPOSE 3000

CMD ["node", "server.js"]
```

**Python (Flask/FastAPI):**
```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN useradd -r -u 1001 app
USER app

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
```

**Static Site (built assets):**
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
```

**Go:**
```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM alpine:3.19
RUN adduser -D -u 1001 app
USER app
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

---

## Step 2: Create GitHub Actions Workflow

Create `.github/workflows/build.yml`:

```yaml
name: Build and Push

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=prod,enable={{is_default_branch}}
            type=sha,prefix=

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

This workflow:
- Builds on every push and PR
- Only pushes to registry on main branch
- Tags images with `:prod` and `:<sha>`

**Note:** The `GITHUB_TOKEN` is automatic - no secrets needed for GHCR.

---

## Step 3: Create Deployment Manifest

Create `deploy.yaml` in your repository root:

```yaml
# Deployment Manifest
# This file tells the infrastructure team how to deploy this service

service:
  # Name for this service (used in docker-compose and routing)
  name: my-app

  # Docker image location (after CI pushes it)
  image: ghcr.io/your-org/your-repo:prod

  # Port your application listens on inside the container
  port: 3000

  # Health check endpoint (optional but recommended)
  health_check: /health

# Domain configuration
domains:
  # Primary domain
  - hostname: myapp.example.com
    # Path prefix (optional, defaults to /)
    path: /

  # Additional domains/subdomains (optional)
  # - hostname: www.myapp.example.com
  #   redirect_to: myapp.example.com

# Environment variables (names only - values provided separately)
environment:
  # Public environment variables (non-sensitive)
  public:
    - NODE_ENV=production
    - LOG_LEVEL=info

  # Secret environment variables (we will create these securely)
  secrets:
    - DATABASE_URL
    - API_KEY

# Persistent storage (optional)
# Paths inside the container that need to persist across restarts
storage:
  - container_path: /app/data
    description: SQLite database and uploads

# Resource hints (optional)
resources:
  # Memory limit (optional)
  memory: 512M

  # CPU shares (optional)
  # cpu: 0.5
```

### Manifest Fields Explained

| Field | Required | Description |
|-------|----------|-------------|
| `service.name` | Yes | Identifier for the service |
| `service.image` | Yes | Full image path after CI pushes |
| `service.port` | Yes | Port the app listens on |
| `service.health_check` | No | Health endpoint path |
| `domains[].hostname` | Yes | Domain(s) to serve the app |
| `domains[].path` | No | Path prefix (default: /) |
| `environment.public` | No | Non-sensitive env vars |
| `environment.secrets` | No | Secret names (values provided separately) |
| `storage[].container_path` | No | Paths needing persistence |
| `resources.memory` | No | Memory limit |

---

## Checklist

Before requesting deployment:

- [ ] `Dockerfile` exists and builds successfully
- [ ] `.github/workflows/build.yml` exists
- [ ] CI has run and pushed image to registry
- [ ] Image is accessible (public or we have access)
- [ ] `deploy.yaml` manifest created with all required fields
- [ ] DNS records point domain to `34.67.186.58` (or tell us to set up DNS)

---

## What Happens Next

After you provide the manifest:

1. We add your service to our docker-compose.yml
2. We configure Caddy to route your domain
3. We create any secrets/data directories needed
4. We deploy and verify

You'll receive the live URL once deployed.

---

## Common Patterns

### App with Database

If your app needs a database, prefer SQLite for simplicity:

```yaml
environment:
  public:
    - DATABASE_URL=file:/app/data/db.sqlite

storage:
  - container_path: /app/data
    description: SQLite database
```

For PostgreSQL/MySQL, let us know - we can discuss options.

### App with File Uploads

```yaml
storage:
  - container_path: /app/uploads
    description: User uploaded files
```

### API with CORS

Note any CORS requirements in the manifest:

```yaml
# Add to your deploy.yaml
notes: |
  This API needs CORS headers for cross-origin requests.
  Allow-Origin: https://frontend.example.com
```

### Multiple Services (Monorepo)

Create separate manifests:
- `deploy.frontend.yaml`
- `deploy.api.yaml`

Or a combined manifest:

```yaml
services:
  - name: frontend
    image: ghcr.io/org/repo:frontend-prod
    port: 80
    domains:
      - hostname: example.com

  - name: api
    image: ghcr.io/org/repo:api-prod
    port: 5000
    domains:
      - hostname: api.example.com
```

---

## Questions?

If you're unsure about any of these requirements, include notes in your manifest and we'll figure it out during deployment.
