# Security Runbook

This document covers security controls, best practices, and procedures for the GCP VM + Docker + Caddy infrastructure.

## Table of Contents

1. [Current Security Controls](#current-security-controls)
2. [Security Verification](#security-verification)
3. [Security Best Practices](#security-best-practices)
4. [Adding New Services Securely](#adding-new-services-securely)
5. [Incident Response](#incident-response)
6. [Regular Maintenance](#regular-maintenance)

---

## Current Security Controls

### Infrastructure Level

#### IAP-Protected SSH Access
- **Control**: SSH access only via Identity-Aware Proxy (IAP)
- **Firewall**: Port 22 restricted to `35.235.240.0/20` (GCP IAP IP range)
- **Access Method**: `gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap`
- **Benefit**: No direct public SSH exposure, requires GCP authentication

#### Shielded VM
- **Secure Boot**: Enabled
- **vTPM**: Enabled
- **Integrity Monitoring**: Enabled
- **Benefit**: Protection against rootkits and boot-level malware

#### Minimal Service Account Scopes
- **Compute VM Service Account**:
  - `devstorage.read_only` - Read-only access to GCS
  - `logging.write` - Write to Cloud Logging
  - `monitoring.write` - Write to Cloud Monitoring
- **Benefit**: Principle of least privilege

#### Per-Service IAM Isolation
- Each external service gets dedicated service account
- Service-specific sudoers rules restrict deployment access
- **Example**: `deploy-opengov-monitor` can only deploy `opengov-monitor` service

#### Firewall Rules
- **HTTP/HTTPS**: Open to `0.0.0.0/0` on ports 80/443 (required for web services)
- **SSH**: Restricted to IAP range only
- **Target Tags**: `web-server`, `ssh-server` for rule targeting

### Network Level

#### Docker Network Isolation
- **Internal Network**: `web` network for container communication
- **Public Exposure**: Only Caddy container exposes ports 80/443
- **Service Communication**: Via internal Docker DNS

#### Automatic TLS
- **Provider**: Let's Encrypt via Caddy
- **Certificate Management**: Fully automatic
- **Renewal**: Handled by Caddy automatically

### Web Server Level

#### Security Headers (Implemented)
All sites served through Caddy include:
- **HSTS**: `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- **Content Type Options**: `X-Content-Type-Options: nosniff`
- **Frame Options**: `X-Frame-Options: DENY`
- **CSP**: `Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;`
- **Referrer Policy**: `Referrer-Policy: strict-origin-when-cross-origin`
- **Permissions Policy**: `Permissions-Policy: geolocation=(), microphone=(), camera=()`

#### Compression
- **Enabled**: gzip and zstd encoding for all responses
- **Benefit**: Faster loading, reduced bandwidth

#### Caddy Admin API
- **Status**: Disabled (`admin off`)
- **Benefit**: Prevents dynamic configuration changes via API
- **Trade-off**: Requires container restart for config changes

### Container Level

#### Resource Limits (Implemented)
All services have CPU and memory limits to prevent resource exhaustion:
- **Example (Caddy)**:
  - Memory limit: 256M
  - Memory reservation: 128M
  - CPU limit: 0.5 cores
  - CPU reservation: 0.25 cores

#### Container Image Scanning (Implemented)
- **Tool**: Trivy
- **Mode**: Report-only (HIGH and CRITICAL vulnerabilities)
- **Command**: `scan-image <image-name>`
- **Frequency**: On-demand or before deployment

### Application Level

#### Service Name Validation
- **Pattern**: `^[a-zA-Z0-9_-]+$` (alphanumeric, hyphens, underscores only)
- **Prevents**: Command injection via service names

#### Read-Only Volume Mounts
- **Caddyfile**: Mounted read-only (`:ro`)
- **Static Files**: Mounted read-only (`:ro`)
- **Benefit**: Containers cannot modify configuration

---

## Security Verification

### Verify Security Headers

```bash
# Check headers on your site
curl -I https://cypherpunk.agency

# Should see:
# strict-transport-security: max-age=31536000; includeSubDomains; preload
# x-content-type-options: nosniff
# x-frame-options: DENY
# content-security-policy: default-src 'self'...
# referrer-policy: strict-origin-when-cross-origin
# permissions-policy: geolocation=()...
```

### Verify Resource Limits

```bash
# SSH to VM
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# Check resource limits are enforced
docker stats

# Should show memory/CPU limits for each container
```

### Verify Trivy Installation

```bash
# Check Trivy is installed
trivy --version

# Scan an image
scan-image caddy:2-alpine

# Should display vulnerability report
```

### Verify IAP SSH Access

```bash
# This should work (via IAP)
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# Direct SSH should NOT work (port 22 not publicly accessible)
ssh your-public-ip  # Should timeout or refuse connection
```

### Verify Firewall Rules

```bash
# List firewall rules
gcloud compute firewall-rules list --filter="name~web-server"

# Should show:
# - web-server-allow-http-https: 0.0.0.0/0 -> ports 80,443
# - web-server-allow-ssh-iap: 35.235.240.0/20 -> port 22
```

### Verify TLS Configuration

```bash
# Check TLS certificate
curl -vI https://cypherpunk.agency 2>&1 | grep -i "SSL\|TLS\|certificate"

# Or use SSL Labs for comprehensive test:
# https://www.ssllabs.com/ssltest/
```

### Verify Container Security

```bash
# Check security options on a container
docker inspect caddy | grep -A 10 SecurityOpt

# Check capabilities
docker inspect caddy | grep -A 10 CapDrop
```

---

## Security Best Practices

### For Infrastructure Team

1. **Keep Terraform State Secure**: Store in GCS bucket with encryption and versioning
2. **Review IAM Regularly**: Audit service account permissions quarterly
3. **Monitor Audit Logs**: Enable Cloud Audit Logs for all privileged operations
4. **Rotate Service Account Keys**: At least every 90 days (automate if possible)
5. **Patch VM Regularly**: Apply security updates monthly
6. **Review Firewall Rules**: Audit rules quarterly, remove unused rules

### For App Teams

1. **Use Official Base Images**: Prefer official images from Docker Hub or verified publishers
2. **Scan Images Before Deploy**: Run `scan-image <your-image>` before deploying
3. **Update Dependencies Regularly**: Keep application dependencies patched
4. **Don't Store Secrets in Images**: Use environment files or Secret Manager
5. **Define Health Checks**: Add `/healthz` endpoint for monitoring
6. **Set Resource Limits**: Define appropriate CPU/memory limits in docker-compose.yml
7. **Use Non-Root User**: Run containers as non-root user when possible

### For All Users

1. **Use IAP for SSH**: Never bypass IAP tunnel for SSH access
2. **Follow Least Privilege**: Request only permissions you need
3. **Report Security Issues**: Contact security team immediately if you find vulnerabilities
4. **Keep Credentials Secure**: Never commit keys or secrets to git
5. **Enable MFA**: Use multi-factor authentication on your GCP account

---

## Adding New Services Securely

When adding a new service, follow these security requirements:

### 1. Service Account Setup

```bash
# Create service account with minimal permissions
gcloud iam service-accounts create deploy-myservice \
    --display-name="Deploy MyService"

# Grant only required roles
gcloud projects add-iam-policy-binding cyberphunk-agency \
    --member="serviceAccount:deploy-myservice@cyberphunk-agency.iam.gserviceaccount.com" \
    --role="roles/iap.tunnelResourceAccessor"

# Create key
gcloud iam service-accounts keys create keys/deploy-myservice-key.json \
    --iam-account=deploy-myservice@cyberphunk-agency.iam.gserviceaccount.com
```

### 2. Docker Compose Configuration

Include these security settings in your service definition:

```yaml
services:
  myservice:
    image: ghcr.io/org/myservice:prod
    container_name: myservice
    restart: unless-stopped
    env_file:
      - /mnt/pd/secrets/myservice.env
    volumes:
      - /mnt/pd/data/myservice:/data
    networks:
      - web
    # SECURITY: Add resource limits
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'
    # SECURITY: Add security profiles (if compatible)
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # Only if needed
```

### 3. Caddyfile Configuration

Add security headers to your domain:

```caddy
myservice.example.com {
    import security_headers  # Use the security headers snippet
    reverse_proxy myservice:PORT
}
```

### 4. Scan Image Before Deploy

```bash
# Scan for vulnerabilities
scan-image ghcr.io/org/myservice:prod

# Review output for HIGH/CRITICAL vulnerabilities
# Fix issues before deploying to production
```

### 5. Create Sudoers Rule

```bash
# SSH to VM
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# Create sudoers file
sudo bash -c 'cat > /etc/sudoers.d/deploy-myservice << EOF
deploy-myservice ALL=(root) NOPASSWD: /usr/local/bin/deploy-service myservice
deploy-myservice ALL=(root) NOPASSWD: /usr/local/bin/service-status myservice
deploy-myservice ALL=(root) NOPASSWD: /usr/local/bin/service-logs myservice
deploy-myservice ALL=(root) NOPASSWD: /usr/local/bin/service-shell myservice
EOF'

# Set correct permissions
sudo chmod 440 /etc/sudoers.d/deploy-myservice
```

---

## Incident Response

### Security Incident Procedures

#### 1. Potential Breach Detected

1. **Isolate**: If breach confirmed, stop affected containers immediately
   ```bash
   docker compose stop affected-service
   ```

2. **Preserve Evidence**: Create snapshots before investigation
   ```bash
   gcloud compute disks snapshot data-disk --snapshot-names=incident-$(date +%Y%m%d-%H%M%S)
   ```

3. **Investigate**: Review logs
   ```bash
   # Container logs
   docker logs affected-service --tail 1000 > incident-logs.txt

   # System logs
   sudo journalctl -u docker --since "1 hour ago" > docker-logs.txt

   # Auth logs
   sudo grep -i "failed\|authentication\|unauthorized" /var/log/auth.log
   ```

4. **Notify**: Contact security team and stakeholders

5. **Remediate**: Fix vulnerability, rotate credentials, update configs

6. **Document**: Write incident report with timeline and lessons learned

#### 2. Suspicious Activity

```bash
# Check active connections
sudo netstat -tupn

# Check running processes
docker exec <container> ps aux

# Check file modifications
find /mnt/pd/data -mtime -1 -type f  # Files modified in last 24 hours

# Review Cloud Audit Logs
gcloud logging read "protoPayload.methodName=~\"compute.*\"" --limit 100
```

#### 3. Compromised Service Account Key

1. **Revoke Key Immediately**:
   ```bash
   gcloud iam service-accounts keys delete KEY_ID \
       --iam-account=deploy-service@cyberphunk-agency.iam.gserviceaccount.com
   ```

2. **Create New Key**:
   ```bash
   gcloud iam service-accounts keys create keys/deploy-service-key.json \
       --iam-account=deploy-service@cyberphunk-agency.iam.gserviceaccount.com
   ```

3. **Update GitHub Secrets**: Replace key in GitHub Actions

4. **Review Audit Logs**: Check for unauthorized access
   ```bash
   gcloud logging read "protoPayload.authenticationInfo.principalEmail=deploy-service@cyberphunk-agency.iam.gserviceaccount.com" --limit 100
   ```

#### 4. Container Vulnerability Discovered

1. **Assess Impact**: Run Trivy scan
   ```bash
   scan-image ghcr.io/org/service:prod
   ```

2. **Check if Exploited**: Review logs for suspicious activity

3. **Update Image**: Build new image with patched dependencies

4. **Deploy Fix**: Update production service
   ```bash
   sudo deploy-service myservice
   ```

---

## Regular Maintenance

### Daily Tasks

- Monitor container health: `docker ps`
- Check disk space: `df -h /mnt/pd`
- Review recent logs: `docker compose logs --tail=100`

### Weekly Tasks

1. **Scan Images for Vulnerabilities**
   ```bash
   # Scan all running containers
   docker ps --format "{{.Image}}" | xargs -I {} scan-image {}
   ```

2. **Review Container Resource Usage**
   ```bash
   docker stats --no-stream
   ```

3. **Check Certificate Status**
   ```bash
   docker compose logs caddy | grep -i "certificate"
   ```

### Monthly Tasks

1. **Update VM Packages**
   ```bash
   sudo apt-get update
   sudo apt-get upgrade -y
   sudo apt-get autoremove -y
   ```

2. **Review Firewall Rules**
   ```bash
   gcloud compute firewall-rules list
   ```

3. **Audit IAM Permissions**
   ```bash
   gcloud projects get-iam-policy cyberphunk-agency
   ```

4. **Review Disk Usage**
   ```bash
   du -h --max-depth=2 /mnt/pd/data
   ```

### Quarterly Tasks

1. **Rotate Service Account Keys**
   ```bash
   # List keys older than 90 days
   gcloud iam service-accounts keys list --iam-account=deploy-service@cyberphunk-agency.iam.gserviceaccount.com

   # Rotate if needed (see Incident Response section)
   ```

2. **Review Security Headers**
   ```bash
   # Check headers still present
   curl -I https://cypherpunk.agency | grep -i "security\|frame\|content-type"
   ```

3. **Security Audit**
   - Review all service account permissions
   - Audit sudoers files: `sudo ls -la /etc/sudoers.d/`
   - Review secrets: `sudo ls -la /mnt/pd/secrets/`
   - Check for unused services/accounts

4. **Backup Verification**
   - Test restore from GCS backup
   - Verify backup encryption

### Annual Tasks

1. **Comprehensive Security Review**
   - Re-run full security assessment
   - Update security-improvements.md with new findings
   - Implement prioritized improvements

2. **Disaster Recovery Test**
   - Test full VM rebuild from Terraform
   - Test data restore from persistent disk snapshot
   - Test service recovery procedures

3. **Compliance Review**
   - Run CIS Docker Benchmark: `docker-bench-security`
   - Review against OWASP Top 10
   - Document compliance status

---

## Security Contacts

### Reporting Security Issues

If you discover a security vulnerability:

1. **DO NOT** open a public GitHub issue
2. **DO NOT** discuss publicly until fixed
3. **DO** report privately to the security team
4. **DO** provide detailed reproduction steps

### Emergency Contacts

- **Infrastructure Team**: (Contact details)
- **Security Team**: (Contact details)
- **On-Call**: (PagerDuty/Phone)

---

## Additional Resources

- [Security Improvements Roadmap](./security-improvements.md) - Full security review and future improvements
- [Infrastructure Documentation](./infrastructure.md) - Architecture and deployment system
- [Operations Guide](./operations.md) - Daily operations and troubleshooting
- [Adding Services Guide](./adding-services.md) - Onboarding new services
- [Containerization Guide](./containerization-guide.md) - App team guidelines

---

## Changelog

- 2026-01-15: Initial security runbook created with current controls (security headers, resource limits, Trivy scanning)
