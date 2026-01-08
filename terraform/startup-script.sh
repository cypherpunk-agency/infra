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
}

:80 {
    respond "Hello from Caddy! Server is running." 200
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
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - web

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
