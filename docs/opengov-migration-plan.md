# OpenGov Monitor: Dev/Prod Split Migration Plan

**Status**: Ready for execution
**Created**: 2026-01-13
**Owner**: Infrastructure team
**Coordination**: OpenSquare team (OpenGov Monitor maintainers)

---

## Overview

This document outlines the step-by-step migration plan to split OpenGov Monitor into separate dev and production deployments on the same VM.

**Current State**:
- Single `opengov-monitor` service
- Domain: `polkadot-treasury-monitor.cypherpunk.agency`
- Image: `ghcr.io/opengov-watch/opengov-monitor:prod`
- Data stored in bind mount: `/mnt/pd/data/opengov-monitor/`

**Target State**:
- Production: `opengov-monitor-prod` at `polkadot-treasury-monitor.cypherpunk.agency`
- Dev: `opengov-monitor-dev` at `dev.polkadot-treasury-monitor.cypherpunk.agency`
- Separate service accounts with isolated access
- Data in bind-mounted directories (`/mnt/pd/data/opengov-monitor-{prod,dev}/`)

**Migration Impact**:
- **Downtime**: ~5-10 minutes during Phase 3
- **Risk Level**: Medium (configuration changes, service restart)
- **Rollback**: Full rollback possible at each phase

---

## Prerequisites

Before starting, gather the following information:

- [ ] GHCR image path (e.g., `ghcr.io/opensquare-network/opengov-monitor`)
- [ ] Confirm existing service account key exists: `keys/deploy-opengov-monitor-key.json`
- [ ] Access to DNS management for `cypherpunk.agency`
- [ ] Communication channel with OpenSquare team
- [ ] GCP project access for creating service accounts

**If any prerequisite is missing, resolve before proceeding.**

---

## Phase 0: Pre-Migration Information Gathering

**Objective**: Document current state and verify prerequisites

**Impact**: None (read-only)

### Steps

1. **Check existing service account key**:
   ```bash
   ls -la keys/deploy-opengov-monitor-key.json
   ```

   **Expected**: File exists (will become prod SA key)

2. **SSH to VM and inspect current configuration**:
   ```bash
   gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
   ```

3. **Document current docker-compose configuration**:
   ```bash
   cat /mnt/pd/stack/docker-compose.yml | grep -A 15 opengov-monitor
   ```

   **Look for**:
   - Image path (GHCR URL)
   - Volume mounts
   - Network configuration

4. **Document current Caddyfile routing**:
   ```bash
   cat /mnt/pd/stack/Caddyfile | grep -A 3 polkadot-treasury-monitor
   ```

5. **Check current container status**:
   ```bash
   docker ps | grep opengov-monitor
   ```

6. **Check data directory**:
   ```bash
   ls -la /mnt/pd/data/ | grep opengov
   du -sh /mnt/pd/data/opengov-monitor/
   ```

7. **Exit SSH**:
   ```bash
   exit
   ```

### Verification

- [ ] GHCR image path confirmed: `ghcr.io/opengov-watch/opengov-monitor:prod`
- [ ] Current storage confirmed: bind mount at `/mnt/pd/data/opengov-monitor/`
- [ ] Service currently running and healthy
- [ ] Domain currently accessible at https://polkadot-treasury-monitor.cypherpunk.agency

### Rollback

Not applicable (read-only phase)

---

### 🚧 CHECKPOINT 0: Confirm Prerequisites

**Before proceeding, confirm:**
- [ ] All information gathered
- [ ] Existing service account key found
- [ ] Current service is healthy
- [ ] Have access to all required systems (GCP, DNS, VM)

**Ready to proceed to Phase 1?**

---

## Phase 1: Preparation (No Service Impact)

**Objective**: Create dev service account, generate key, prepare infrastructure

**Impact**: None on running services

### Steps

1. **Set environment variable**:
   ```bash
   SERVICE_NAME=opengov-monitor-dev
   ```

2. **Create dev service account**:
   ```bash
   gcloud iam service-accounts create deploy-$SERVICE_NAME \
     --display-name="Deploy OpenGov Monitor Dev" \
     --project=cyberphunk-agency
   ```

   **Expected output**: `Created service account [deploy-opengov-monitor-dev]`

3. **Grant IAP tunnel access**:
   ```bash
   gcloud projects add-iam-policy-binding cyberphunk-agency \
     --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
     --role="roles/iap.tunnelResourceAccessor" \
     --quiet
   ```

4. **Grant compute instance admin**:
   ```bash
   gcloud projects add-iam-policy-binding cyberphunk-agency \
     --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
     --role="roles/compute.instanceAdmin.v1" \
     --quiet
   ```

5. **Grant service account user role**:
   ```bash
   gcloud projects add-iam-policy-binding cyberphunk-agency \
     --member="serviceAccount:deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountUser" \
     --quiet
   ```

6. **Create and download key**:
   ```bash
   gcloud iam service-accounts keys create keys/deploy-$SERVICE_NAME-key.json \
     --iam-account=deploy-$SERVICE_NAME@cyberphunk-agency.iam.gserviceaccount.com
   ```

   **Expected**: Key file created at `keys/deploy-opengov-monitor-dev-key.json`

7. **Rename existing key to prod** (if needed):
   ```bash
   # Only if current key is named deploy-opengov-monitor-key.json
   mv keys/deploy-opengov-monitor-key.json keys/deploy-opengov-monitor-prod-key.json
   ```

### Verification

- [ ] Dev service account exists: `gcloud iam service-accounts list | grep opengov-monitor-dev`
- [ ] Dev key file exists: `ls keys/deploy-opengov-monitor-dev-key.json`
- [ ] Prod key file exists: `ls keys/deploy-opengov-monitor-prod-key.json`

### Rollback

If something goes wrong, delete the service account:
```bash
gcloud iam service-accounts delete deploy-opengov-monitor-dev@cyberphunk-agency.iam.gserviceaccount.com --quiet
rm keys/deploy-opengov-monitor-dev-key.json
```

---

### 🚧 CHECKPOINT 1: Confirm Service Accounts

**Before proceeding, confirm:**
- [ ] Dev service account created successfully
- [ ] Both key files exist (prod and dev)
- [ ] IAM bindings confirmed
- [ ] No errors in service account creation

**Ready to proceed to Phase 2?**

---

## Phase 2: DNS Setup (External)

**Objective**: Configure DNS for dev subdomain

**Impact**: None on running services

### Steps

1. **Add DNS A record** (via your DNS provider):
   - **Record type**: A
   - **Name**: `dev.polkadot-treasury-monitor.cypherpunk.agency`
   - **Value**: `34.67.186.58` (static IP)
   - **TTL**: 300 (5 minutes)

2. **Wait for DNS propagation** (5-15 minutes):
   ```bash
   # Check DNS resolution
   nslookup dev.polkadot-treasury-monitor.cypherpunk.agency
   ```

   **Expected**: Returns `34.67.186.58`

3. **Verify from multiple locations** (optional):
   ```bash
   dig +short dev.polkadot-treasury-monitor.cypherpunk.agency @8.8.8.8
   dig +short dev.polkadot-treasury-monitor.cypherpunk.agency @1.1.1.1
   ```

### Verification

- [ ] DNS resolves to correct IP
- [ ] Resolution works from multiple DNS servers

### Rollback

Delete the DNS A record if needed (no impact on existing service)

---

### 🚧 CHECKPOINT 2: Confirm DNS

**Before proceeding, confirm:**
- [ ] Dev domain resolves to 34.67.186.58
- [ ] Prod domain still resolves correctly
- [ ] DNS propagation complete

**Ready to proceed to Phase 3?**

---

## Phase 3: VM Configuration (⚠️ Service Downtime)

**Objective**: Update docker-compose, Caddyfile, and directory structure

**Impact**: ~5-10 minutes downtime while reconfiguring

**IMPORTANT**: This phase includes service interruption. Proceed during maintenance window.

### Steps

1. **SSH to VM**:
   ```bash
   gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
   ```

2. **Navigate to stack directory**:
   ```bash
   cd /mnt/pd/stack
   ```

3. **Backup current configuration**:
   ```bash
   sudo cp docker-compose.yml docker-compose.yml.backup-$(date +%Y%m%d)
   sudo cp Caddyfile Caddyfile.backup-$(date +%Y%m%d)
   ```

4. **Backup current data** (optional but recommended):
   ```bash
   # Create a tarball backup of the data directory
   sudo tar czf /mnt/pd/data/opengov-monitor-backup-$(date +%Y%m%d-%H%M).tar.gz \
     -C /mnt/pd/data opengov-monitor
   ```

   **Expected**: Backup file created at `/mnt/pd/data/opengov-monitor-backup-YYYYMMDD-HHMM.tar.gz`

5. **Stop current service**:
   ```bash
   sudo docker compose stop opengov-monitor
   ```

   **Expected**: `Container opengov-monitor Stopped`

---

### 🚧 CHECKPOINT 3A: Service Stopped

**Verify:**
- [ ] Backups created successfully
- [ ] Service stopped cleanly
- [ ] Ready to modify configuration files

**Continue with configuration updates?**

---

6. **Edit docker-compose.yml**:
   ```bash
   sudo nano docker-compose.yml
   ```

   **Find the `opengov-monitor` service and replace it with:**
   ```yaml
   opengov-monitor-prod:
     image: ghcr.io/opengov-watch/opengov-monitor:production
     container_name: opengov-monitor-prod
     restart: unless-stopped
     volumes:
       - /mnt/pd/data/opengov-monitor-prod:/data
     networks:
       - web

   opengov-monitor-dev:
     image: ghcr.io/opengov-watch/opengov-monitor:main
     container_name: opengov-monitor-dev
     restart: unless-stopped
     volumes:
       - /mnt/pd/data/opengov-monitor-dev:/data
     networks:
       - web
   ```

   **Save and exit** (Ctrl+O, Enter, Ctrl+X)

7. **Edit Caddyfile**:
   ```bash
   sudo nano Caddyfile
   ```

   **Find the polkadot-treasury-monitor section and update to:**
   ```
   polkadot-treasury-monitor.cypherpunk.agency {
       reverse_proxy opengov-monitor-prod:80
   }

   dev.polkadot-treasury-monitor.cypherpunk.agency {
       reverse_proxy opengov-monitor-dev:80
   }
   ```

   **Save and exit** (Ctrl+O, Enter, Ctrl+X)

8. **Create data directories**:
   ```bash
   sudo mkdir -p /mnt/pd/data/opengov-monitor-prod
   sudo mkdir -p /mnt/pd/data/opengov-monitor-dev
   sudo chmod 777 /mnt/pd/data/opengov-monitor-{prod,dev}
   ```

9. **Copy existing data to prod directory**:
   ```bash
   # Copy data from current directory to prod directory
   sudo cp -a /mnt/pd/data/opengov-monitor/. /mnt/pd/data/opengov-monitor-prod/
   ```

   **Or extract from backup if preferred**:
   ```bash
   sudo tar xzf /mnt/pd/data/opengov-monitor-backup-*.tar.gz -C /mnt/pd/data/opengov-monitor-prod/ --strip-components=1
   ```

10. **Verify configuration syntax**:
    ```bash
    # Check docker-compose syntax
    sudo docker compose config
    ```

    **Expected**: No errors, shows parsed configuration

---

### 🚧 CHECKPOINT 3B: Configuration Updated

**Verify:**
- [ ] Backups exist
- [ ] docker-compose.yml updated with both services
- [ ] Caddyfile updated with both domains
- [ ] Data directories created
- [ ] Configuration syntax valid
- [ ] Data copied to prod directory (if applicable)

**Ready to update sudoers and start services?**

---

### Verification

Review the changes:
```bash
cat docker-compose.yml | grep -A 10 opengov-monitor
cat Caddyfile | grep -A 3 polkadot-treasury-monitor
ls -la /mnt/pd/data/ | grep opengov
```

### Rollback

If configuration is incorrect:
```bash
# Restore backups
sudo cp docker-compose.yml.backup-YYYYMMDD docker-compose.yml
sudo cp Caddyfile.backup-YYYYMMDD Caddyfile

# Restart original service
sudo docker compose up -d opengov-monitor
```

---

## Phase 4: Service Account Access Control

**Objective**: Configure sudoers rules for both service accounts

**Impact**: None on running services (still stopped)

### Steps

1. **Update prod sudoers file** (or create if doesn't exist):
   ```bash
   echo 'deploy-opengov-monitor-prod ALL=(ALL) NOPASSWD: /usr/local/bin/deploy-service opengov-monitor-prod
   deploy-opengov-monitor-prod ALL=(ALL) NOPASSWD: /usr/local/bin/service-status opengov-monitor-prod
   deploy-opengov-monitor-prod ALL=(ALL) NOPASSWD: /usr/local/bin/service-logs opengov-monitor-prod
   deploy-opengov-monitor-prod ALL=(ALL) NOPASSWD: /usr/local/bin/service-logs opengov-monitor-prod *
   deploy-opengov-monitor-prod ALL=(ALL) NOPASSWD: /usr/local/bin/service-shell opengov-monitor-prod' | sudo tee /etc/sudoers.d/deploy-opengov-monitor-prod
   ```

2. **Set correct permissions on prod sudoers**:
   ```bash
   sudo chmod 440 /etc/sudoers.d/deploy-opengov-monitor-prod
   ```

3. **Create dev sudoers file**:
   ```bash
   echo 'deploy-opengov-monitor-dev ALL=(ALL) NOPASSWD: /usr/local/bin/deploy-service opengov-monitor-dev
   deploy-opengov-monitor-dev ALL=(ALL) NOPASSWD: /usr/local/bin/service-status opengov-monitor-dev
   deploy-opengov-monitor-dev ALL=(ALL) NOPASSWD: /usr/local/bin/service-logs opengov-monitor-dev
   deploy-opengov-monitor-dev ALL=(ALL) NOPASSWD: /usr/local/bin/service-logs opengov-monitor-dev *
   deploy-opengov-monitor-dev ALL=(ALL) NOPASSWD: /usr/local/bin/service-shell opengov-monitor-dev' | sudo tee /etc/sudoers.d/deploy-opengov-monitor-dev
   ```

4. **Set correct permissions on dev sudoers**:
   ```bash
   sudo chmod 440 /etc/sudoers.d/deploy-opengov-monitor-dev
   ```

5. **Verify sudoers syntax**:
   ```bash
   sudo visudo -c
   ```

   **Expected**: `parsed OK`

6. **Remove old sudoers file** (if exists):
   ```bash
   # Only if there's an old deploy-opengov-monitor file
   sudo rm /etc/sudoers.d/deploy-opengov-monitor
   ```

### Verification

- [ ] Prod sudoers file exists with correct permissions
- [ ] Dev sudoers file exists with correct permissions
- [ ] Sudoers syntax valid
- [ ] Old file removed (if applicable)

### Rollback

Remove new files and restore old:
```bash
sudo rm /etc/sudoers.d/deploy-opengov-monitor-{prod,dev}
# Restore old if backed up
sudo cp /etc/sudoers.d/deploy-opengov-monitor.backup /etc/sudoers.d/deploy-opengov-monitor
```

---

### 🚧 CHECKPOINT 4: Access Control Configured

**Before proceeding, confirm:**
- [ ] Both sudoers files created
- [ ] Permissions set correctly (440)
- [ ] Syntax validation passed
- [ ] Ready to start services

**Ready to proceed to Phase 5?**

---

## Phase 5: Service Startup

**Objective**: Start both services and verify they're running

**Impact**: Services coming back online

### Steps

1. **Pull images** (if not already present):
   ```bash
   sudo docker compose pull opengov-monitor-prod opengov-monitor-dev
   ```

2. **Start both services**:
   ```bash
   sudo docker compose up -d opengov-monitor-prod opengov-monitor-dev
   ```

   **Expected**:
   ```
   Container opengov-monitor-prod  Started
   Container opengov-monitor-dev   Started
   ```

3. **Verify containers are running**:
   ```bash
   docker ps | grep opengov-monitor
   ```

   **Expected**: Two containers, both with status "Up"

4. **Check logs for errors**:
   ```bash
   sudo docker compose logs --tail=50 opengov-monitor-prod
   sudo docker compose logs --tail=50 opengov-monitor-dev
   ```

   **Look for**: No critical errors, services started successfully

5. **Wait for Caddy to provision TLS certificates** (~30 seconds):
   ```bash
   sudo docker compose logs -f caddy
   ```

   **Look for**: Lines like `certificate obtained successfully`

6. **Restart Caddy to ensure routing works**:
   ```bash
   sudo docker compose restart caddy
   ```

### Verification

- [ ] Both containers running
- [ ] No errors in logs
- [ ] Caddy logs show TLS certificates obtained
- [ ] Caddy restarted successfully

### Rollback

If services fail to start:
```bash
# Stop new services
sudo docker compose stop opengov-monitor-{prod,dev}

# Restore old configuration
sudo cp docker-compose.yml.backup-YYYYMMDD docker-compose.yml
sudo cp Caddyfile.backup-YYYYMMDD Caddyfile

# Restart old service
sudo docker compose up -d opengov-monitor
```

---

### 🚧 CHECKPOINT 5: Services Running

**Before proceeding, confirm:**
- [ ] Both containers running with no restart loops
- [ ] Logs show healthy startup
- [ ] TLS certificates obtained
- [ ] Ready to test externally

**Ready to proceed to Phase 6?**

---

## Phase 6: Testing

**Objective**: Verify both URLs are accessible and working correctly

**Impact**: None (testing only)

### Steps

1. **Exit SSH** (test from local machine):
   ```bash
   exit
   ```

2. **Test production URL**:
   ```bash
   curl -I https://polkadot-treasury-monitor.cypherpunk.agency
   ```

   **Expected**: `HTTP/2 200` or `HTTP/2 301/302` (redirect)

3. **Test dev URL**:
   ```bash
   curl -I https://dev.polkadot-treasury-monitor.cypherpunk.agency
   ```

   **Expected**: `HTTP/2 200` or `HTTP/2 301/302` (redirect)

4. **Test in browser**:
   - Open https://polkadot-treasury-monitor.cypherpunk.agency
   - Open https://dev.polkadot-treasury-monitor.cypherpunk.agency

   **Expected**: Both load without certificate errors

5. **Check container health** (SSH back in if needed):
   ```bash
   gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap
   docker ps
   docker stats --no-stream | grep opengov
   ```

### Verification

- [ ] Production URL accessible
- [ ] Dev URL accessible
- [ ] No TLS certificate errors
- [ ] Both services responding correctly
- [ ] Containers healthy (not excessive CPU/memory)

### Troubleshooting

**If URLs don't load**:
```bash
# Check Caddy logs
sudo docker compose logs caddy | grep -i error

# Check service logs
sudo docker compose logs opengov-monitor-prod
sudo docker compose logs opengov-monitor-dev

# Verify DNS
dig +short dev.polkadot-treasury-monitor.cypherpunk.agency
```

**If certificate errors**:
```bash
# Restart Caddy
sudo docker compose restart caddy

# Wait 30 seconds and test again
```

---

### 🚧 CHECKPOINT 6: Services Accessible

**Before proceeding, confirm:**
- [ ] Both URLs load correctly in browser
- [ ] No certificate warnings
- [ ] Services functioning as expected
- [ ] Ready to coordinate with OpenSquare team

**Ready to proceed to Phase 7?**

---

## Phase 7: Team Coordination

**Objective**: Send credentials and instructions to OpenSquare team

**Impact**: None (communication only)

### Steps

1. **Prepare dev service account key for sending**:
   ```bash
   # Verify file exists
   ls -la keys/deploy-opengov-monitor-dev-key.json
   ```

2. **Send to OpenSquare team** (secure channel):
   - File: `keys/deploy-opengov-monitor-dev-key.json`
   - Instructions: Point to updated workflow example below

3. **Provide workflow example**:

```yaml
name: Deploy

on:
  push:
    branches: [main, production]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set deployment target
        id: target
        run: |
          if [ "${{ github.ref }}" == "refs/heads/production" ]; then
            echo "service=opengov-monitor-prod" >> $GITHUB_OUTPUT
            echo "tag=production" >> $GITHUB_OUTPUT
            echo "sa_key=GCP_SA_KEY_PROD" >> $GITHUB_OUTPUT
          else
            echo "service=opengov-monitor-dev" >> $GITHUB_OUTPUT
            echo "tag=main" >> $GITHUB_OUTPUT
            echo "sa_key=GCP_SA_KEY_DEV" >> $GITHUB_OUTPUT
          fi

      - name: Log in to GHCR
        run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

      - name: Build and push image
        run: |
          docker build -t ghcr.io/${{ github.repository }}:${{ steps.target.outputs.tag }} .
          docker push ghcr.io/${{ github.repository }}:${{ steps.target.outputs.tag }}

      - name: Deploy to GCP
        run: |
          echo "${{ secrets[steps.target.outputs.sa_key] }}" > /tmp/sa-key.json
          gcloud auth activate-service-account --key-file=/tmp/sa-key.json
          gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
            --command="sudo /usr/local/bin/deploy-service ${{ steps.target.outputs.service }}"
          rm /tmp/sa-key.json
```

4. **Explain GitHub secrets setup**:
   - Add `GCP_SA_KEY_DEV` secret (new dev key)
   - Rename or add `GCP_SA_KEY_PROD` secret (existing prod key)

5. **Coordinate testing**:
   - Agree on timeline for workflow update
   - Plan test deployments to both environments

### Verification

- [ ] Dev key sent securely
- [ ] Workflow example provided
- [ ] Team acknowledged receipt
- [ ] Timeline agreed

---

### 🚧 CHECKPOINT 7: Team Coordinated

**Before proceeding, confirm:**
- [ ] OpenSquare team has dev key
- [ ] Workflow example provided
- [ ] GitHub secrets strategy agreed
- [ ] Team ready to update their workflow

**Ready to proceed to Phase 8?**

---

## Phase 8: Workflow Update (OpenSquare Team Side)

**Objective**: OpenSquare team updates their GitHub Actions workflow

**Impact**: None (their side)

**Note**: This phase is performed by the OpenSquare team. We monitor and assist.

### Their Steps

1. Add GitHub secrets to their repo:
   - `GCP_SA_KEY_DEV` (new dev key we provided)
   - `GCP_SA_KEY_PROD` (their existing key, renamed for clarity)

2. Update `.github/workflows/deploy.yml` with the conditional logic

3. Test deployment to dev:
   - Push commit to `main` branch
   - Verify GitHub Actions deploys to `opengov-monitor-dev`
   - Check https://dev.polkadot-treasury-monitor.cypherpunk.agency updates

4. Test deployment to prod:
   - Push commit to `production` branch
   - Verify GitHub Actions deploys to `opengov-monitor-prod`
   - Check https://polkadot-treasury-monitor.cypherpunk.agency updates

### Our Monitoring

Monitor deployments on our side:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

# Watch for deployment activity
watch -n 2 'docker ps | grep opengov-monitor'

# Check logs when deployment happens
sudo docker compose logs -f opengov-monitor-dev
sudo docker compose logs -f opengov-monitor-prod
```

### Verification

- [ ] Dev deployment successful (main branch)
- [ ] Prod deployment successful (production branch)
- [ ] Both services updated correctly
- [ ] No deployment errors

### Troubleshooting

**If deployment fails**:
1. Check GitHub Actions logs in their repo
2. Verify service account permissions
3. Test SSH access manually:
   ```bash
   # From their repo, using their dev key
   gcloud auth activate-service-account --key-file=dev-key.json
   gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
     --command="sudo /usr/local/bin/deploy-service opengov-monitor-dev"
   ```

---

### 🚧 CHECKPOINT 8: Deployments Working

**Before proceeding, confirm:**
- [ ] Both deployment pipelines tested
- [ ] Dev deploys from main branch
- [ ] Prod deploys from production branch
- [ ] No deployment failures
- [ ] Team confirms everything working

**Ready to proceed to Phase 9?**

---

## Phase 9: Documentation Update & Completion

**Objective**: Update documentation and mark migration complete

**Impact**: None (documentation only)

### Steps

1. **Update `docs/deployed-services.md`**:
   - Remove pending migration note from `opengov-monitor`
   - Move `opengov-monitor-prod` and `opengov-monitor-dev` from "Future Deployments" to "Services"
   - Update "Last updated" date
   - Fill in actual GHCR image path
   - Add deployment dates

2. **Commit documentation changes**:
   ```bash
   git add docs/deployed-services.md
   git commit -m "docs: update deployed services after opengov dev/prod split"
   git push
   ```

3. **Archive this migration plan**:
   - Add "Status: Completed on YYYY-MM-DD" to the top
   - Consider moving to `docs/archive/` or adding completion note

4. **Clean up backups** (after 7 days):
   ```bash
   # SSH to VM
   gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap

   # List backups
   ls -lh /mnt/pd/data/opengov-monitor-backup-*

   # Remove old backups (after confirming everything works)
   sudo rm /mnt/pd/data/opengov-monitor-backup-*
   sudo rm /mnt/pd/stack/docker-compose.yml.backup-*
   sudo rm /mnt/pd/stack/Caddyfile.backup-*
   ```

5. **Remove old data directory** (optional, after confirming migration successful):
   ```bash
   # ONLY after confirming both dev and prod work correctly
   # Keep for at least a week before removing
   sudo rm -rf /mnt/pd/data/opengov-monitor/
   ```

### Verification

- [ ] Documentation updated and committed
- [ ] Migration plan marked complete
- [ ] Backups cleaned up (after grace period)
- [ ] Old volume removed (optional)

---

### 🎉 CHECKPOINT 9: Migration Complete!

**Final verification checklist:**
- [ ] Production service running at polkadot-treasury-monitor.cypherpunk.agency
- [ ] Dev service running at dev.polkadot-treasury-monitor.cypherpunk.agency
- [ ] Separate service accounts working
- [ ] Deployments working from both branches
- [ ] Documentation updated
- [ ] Team satisfied with setup

**Migration status: COMPLETE**

---

## Post-Migration Notes

### Monitoring

Monitor both services for the first week:
```bash
# Check container health
docker ps | grep opengov-monitor

# Check logs for errors
docker compose logs --tail=100 opengov-monitor-prod
docker compose logs --tail=100 opengov-monitor-dev

# Check resource usage
docker stats --no-stream | grep opengov
```

### Future Domain Change

When ready to migrate to `monitor.opengov.watch`:
1. Add DNS A record for `monitor.opengov.watch` → `34.67.186.58`
2. Add DNS A record for `dev.monitor.opengov.watch` → `34.67.186.58`
3. Update Caddyfile to add new domains (can have multiple domains per service)
4. Restart Caddy to provision new certificates
5. Update documentation

### Rollback (If Needed Post-Migration)

If critical issues found after migration:
1. SSH to VM
2. Restore backup configurations:
   ```bash
   cd /mnt/pd/stack
   sudo cp docker-compose.yml.backup-YYYYMMDD docker-compose.yml
   sudo cp Caddyfile.backup-YYYYMMDD Caddyfile
   ```
3. Restore old sudoers (if backed up)
4. Stop new services: `sudo docker compose stop opengov-monitor-{prod,dev}`
5. Start old service: `sudo docker compose up -d opengov-monitor`
6. Notify OpenSquare team to revert workflow changes

---

## Contact

**Questions or issues during migration?**
- Infrastructure team: [your contact]
- OpenSquare team: [their contact]
- Emergency rollback: Follow rollback procedures in each phase

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2026-01-13 | Initial migration plan created | Infrastructure team |
| YYYY-MM-DD | Migration completed | TBD |
