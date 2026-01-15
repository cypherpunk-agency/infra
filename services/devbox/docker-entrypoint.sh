#!/bin/bash
set -e

# Set SSH password for devuser (same as code-server password)
echo "devuser:${DEVBOX_PASSWORD:-changeme}" | chpasswd

# Start SSH
/usr/sbin/sshd

# Configure code-server
if [ ! -f /home/devuser/.config/code-server/config.yaml ]; then
    sudo -u devuser mkdir -p /home/devuser/.config/code-server
    cat > /home/devuser/.config/code-server/config.yaml <<EOF
bind-addr: 0.0.0.0:8443
auth: password
password: ${DEVBOX_PASSWORD:-changeme}
cert: false
EOF
fi

# Start code-server
exec sudo -u devuser code-server --bind-addr 0.0.0.0:8443 /workspace
