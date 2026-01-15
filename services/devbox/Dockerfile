FROM nikolaik/python-nodejs:python3.12-nodejs22

# Install dependencies
RUN apt-get update && apt-get install -y \
    openssh-server build-essential git vim nano htop curl sudo \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    echo 'PermitRootLogin no' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PubkeyAuthentication no' >> /etc/ssh/sshd_config

# Create devuser with UID 1000 (delete existing UID 1000 user if present)
RUN (getent passwd 1000 && userdel -r $(getent passwd 1000 | cut -d: -f1) || true) && \
    useradd -m -s /bin/bash -u 1000 devuser && \
    mkdir -p /home/devuser/.ssh && \
    chown -R devuser:devuser /home/devuser

WORKDIR /workspace
RUN chown devuser:devuser /workspace

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8443 2222

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
