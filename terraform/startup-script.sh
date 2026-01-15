#!/bin/bash
set -e

LOG_FILE="/var/log/startup-script.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Startup script started at $(date) ==="

# -----------------------------------------------------------------------------
# 1. Install Docker if not present
# -----------------------------------------------------------------------------
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    echo "Docker installed successfully"
else
    echo "Docker already installed"
fi

# -----------------------------------------------------------------------------
# 1b. Create deploy script for CI/CD
# -----------------------------------------------------------------------------
cat > /usr/local/bin/deploy-service << 'DEPLOYSCRIPT'
#!/bin/bash
set -e

SERVICE_NAME="$1"
STACK_DIR="/mnt/pd/stack"

if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: deploy-service <service-name>"
    exit 1
fi

if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid service name"
    exit 1
fi

if ! grep -q "^  ${SERVICE_NAME}:" "$STACK_DIR/docker-compose.yml"; then
    echo "Error: Service '$SERVICE_NAME' not found in docker-compose.yml"
    exit 1
fi

cd "$STACK_DIR"
echo "Deploying $SERVICE_NAME..."
docker compose pull "$SERVICE_NAME"
docker compose up -d "$SERVICE_NAME"
echo "Deploy complete: $SERVICE_NAME"
DEPLOYSCRIPT

chmod 755 /usr/local/bin/deploy-service

# Service status script
cat > /usr/local/bin/service-status << 'SCRIPT'
#!/bin/bash
SERVICE_NAME="$1"
if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: service-status <service-name>"
    exit 1
fi
echo "=== Container Status ==="
docker ps --filter "name=$SERVICE_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
echo ""
echo "=== Health Check ==="
docker inspect "$SERVICE_NAME" --format "{{.State.Health.Status}}" 2>/dev/null || echo "No healthcheck configured"
SCRIPT
chmod 755 /usr/local/bin/service-status

# Service logs script
cat > /usr/local/bin/service-logs << 'SCRIPT'
#!/bin/bash
SERVICE_NAME="$1"
LINES="${2:-100}"
if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: service-logs <service-name> [lines]"
    exit 1
fi
docker logs "$SERVICE_NAME" --tail "$LINES"
SCRIPT
chmod 755 /usr/local/bin/service-logs

# Service shell script
cat > /usr/local/bin/service-shell << 'SCRIPT'
#!/bin/bash
SERVICE_NAME="$1"
if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: service-shell <service-name>"
    exit 1
fi
docker exec -it "$SERVICE_NAME" /bin/sh
SCRIPT
chmod 755 /usr/local/bin/service-shell

echo "Service scripts installed"

# -----------------------------------------------------------------------------
# 1c. Install Trivy for container image scanning
# -----------------------------------------------------------------------------
if ! command -v trivy &> /dev/null; then
    echo "Installing Trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
    echo "Trivy installed successfully"
else
    echo "Trivy already installed"
fi

# Create image scan helper script
cat > /usr/local/bin/scan-image << 'SCANSCRIPT'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: scan-image <image-name>"
    echo "Example: scan-image caddy:2-alpine"
    echo "Example: scan-image ghcr.io/org/repo:prod"
    exit 1
fi

echo "Scanning $1 for vulnerabilities..."
trivy image --severity HIGH,CRITICAL "$1"
SCANSCRIPT
chmod +x /usr/local/bin/scan-image

echo "Trivy scan script installed"

# -----------------------------------------------------------------------------
# 2. Mount persistent disk at /mnt/pd
# -----------------------------------------------------------------------------
MOUNT_POINT="/mnt/pd"
DEVICE="/dev/disk/by-id/google-data-disk"

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "Setting up persistent disk..."

    mkdir -p "$MOUNT_POINT"

    # Format disk if it's new (no filesystem)
    if ! blkid "$DEVICE" &> /dev/null; then
        echo "Formatting new disk..."
        mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$DEVICE"
    fi

    # Add to fstab if not present
    if ! grep -q "$MOUNT_POINT" /etc/fstab; then
        echo "$DEVICE $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
    fi

    mount "$MOUNT_POINT"
    echo "Persistent disk mounted at $MOUNT_POINT"
else
    echo "Persistent disk already mounted"
fi

# -----------------------------------------------------------------------------
# 3. Create directory structure
# -----------------------------------------------------------------------------
echo "Setting up directory structure..."
mkdir -p "$MOUNT_POINT/stack"
mkdir -p "$MOUNT_POINT/data"
mkdir -p "$MOUNT_POINT/data/static"
mkdir -p "$MOUNT_POINT/secrets"

# -----------------------------------------------------------------------------
# 4. Set up initial stack if not present
# -----------------------------------------------------------------------------
COMPOSE_FILE="$MOUNT_POINT/stack/docker-compose.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Creating initial Docker Compose stack..."

    # Create Caddyfile
    cat > "$MOUNT_POINT/stack/Caddyfile" << 'EOF'
{
    admin off
    servers {
        protocols h1 h2 h3
    }
}

# Security headers snippet
(security_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "geolocation=(), microphone=(), camera=()"
    }
    encode gzip zstd
}

cypherpunk.agency {
    import security_headers
    root * /static
    file_server
}
EOF

    # Create docker-compose.yml
    cat > "$COMPOSE_FILE" << 'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - /mnt/pd/data/static:/static:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - web
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.25'

networks:
  web:
    name: web

volumes:
  caddy_data:
  caddy_config:
EOF

    echo "Initial stack created"
fi

# -----------------------------------------------------------------------------
# 5. Start the stack
# -----------------------------------------------------------------------------
echo "Starting Docker Compose stack..."
cd "$MOUNT_POINT/stack"
docker compose pull
docker compose up -d

echo "=== Startup script completed at $(date) ==="
