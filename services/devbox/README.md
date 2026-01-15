# Devbox

Remote development container with web IDE and SSH access.

## Image

- **Base**: `nikolaik/python-nodejs:python3.12-nodejs22`
- **Tools**: Node.js 22, Python 3.12, Git, gh CLI, Claude Code, vim, nano, htop, sudo
- **Services**: code-server (web IDE), OpenSSH server
- **User**: `devuser` (UID 1000 - must match host directory ownership)

## Access

- **Web IDE**: https://code.cypherpunk.agency
- **SSH (service-shell)**: `gcloud compute ssh web-server ... sudo service-shell devbox`
- **SSH (direct)**: Port 2222 via IAP tunnel

## Authentication

Single password for both web IDE and SSH:
- Set in `/mnt/pd/secrets/devbox.env` as `DEVBOX_PASSWORD`
- SSH uses password auth (no pubkey)

## Persistence

All data stored in `/mnt/pd/data/services/devbox/`:
- `workspace/` - Code and projects
- `sites/` - Static websites (served via Caddy with additional config)
- `.ssh/` - SSH keys for git
- `.config/` - Tool configurations
- `.local/` - VS Code extensions and settings

## Key Learnings

1. **UID 1000 required**: devuser must be UID 1000 to match host directory permissions. Base image has existing UID 1000 user (pn) that must be deleted first.

2. **sudo required**: Base image doesn't include sudo by default, needed for entrypoint script.

3. **Extension persistence**: Must mount `.local` directory to persist VS Code extensions across restarts.

4. **Password auth**: Simpler than SSH keys for both access methods. Password set via `chpasswd` in entrypoint.

## Building

```bash
cd services/devbox
docker build -t ghcr.io/cypherpunk-agency/infra-devbox:latest .
docker push ghcr.io/cypherpunk-agency/infra-devbox:latest
```

Package must be public on GitHub for VM to pull without authentication.

## Deployment

```bash
# Update on VM
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="cd /mnt/pd/stack && sudo docker compose pull devbox && sudo docker compose up -d devbox"
```
