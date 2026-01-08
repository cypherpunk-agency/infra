Below is a deployable, implementation-ready specification for **Option B: “Terraform provisions a single Compute Engine VM and bootstraps container infrastructure via startup script; CI/CD updates individual apps by pushing new container images.”**

---

# Spec: Single VM + Docker Compose via Startup Script + Per-repo CI Deploy

## 1. Objectives and non-goals

### Objectives

* Provision a **single Compute Engine VM** (no HA) capable of running multiple websites from different repos.
* Ensure the VM is **self-bootstrapping**: on first boot (and on rebuild) it installs Docker/Compose and starts the desired container stack automatically.
* Standardize a **per-repo CI/CD** flow where each app can deploy independently by building and pushing an image and triggering a targeted service update on the VM.
* Persist state (notably **SQLite**) on a **Persistent Disk** mounted on the VM.
* Provide deterministic rollback and basic observability (logs + health checks).

### Non-goals

* Kubernetes/GKE, multi-node orchestration, autoscaling.
* High availability, multi-zone failover.
* Fully managing application configuration changes purely via Terraform on every commit (Terraform is for infra, not continuous app deploys).

---

## 2. High-level architecture

### Components

1. **Terraform-managed infrastructure**

* Compute Engine VM (Ubuntu LTS recommended)
* Persistent Disk (PD) for application state (SQLite, uploads, etc.)
* Static external IPv4 address (recommended for DNS stability)
* Firewall rules (allow 22, 80, 443; deny everything else by default)
* Service account for the VM (least-privilege; optional)

2. **Bootstrap (startup script)**

* Runs on VM boot (cloud-init / metadata startup script).
* Installs Docker Engine + Docker Compose plugin.
* Mounts the persistent disk at a fixed mount point (e.g., `/mnt/pd`).
* Fetches a “stack definition” (compose bundle + configs) from a canonical source.
* Starts/updates the stack using `docker compose up -d`.
* Ensures services restart on reboot.

3. **Runtime stack on the VM**

* Reverse proxy: Nginx/Caddy/Traefik (choose one; Caddy is simplest for automatic TLS, Nginx is most familiar).
* One container per website/service (site-a, site-b, …).
* Optional: a lightweight “ops” container for cron-like tasks (but you can also use systemd timers on host).

4. **CI/CD per app repo**

* Builds Docker image, pushes to registry (Artifact Registry or GHCR).
* Triggers targeted update on VM for that service only.

---

## 3. Source of truth and repositories

### 3.1 Terraform repository (infra repo)

Responsibilities:

* All GCP resources for the VM.
* Metadata startup script content and parameters.
* Outputs: VM name, zone, IP, disk name, registry location, etc.

### 3.2 Stack repository (ops/stack repo)

This is the canonical source that the startup script pulls from to start the stack. It should include:

* `docker-compose.yml`
* reverse proxy config (e.g., `Caddyfile` or Nginx site configs)
* environment templates, e.g., `env/site-a.env`
* a small `deploy.sh` script that:

  * validates config
  * pulls images
  * performs `docker compose up -d`
  * optionally prunes old images

This repo changes infrequently compared to application repos.

### 3.3 Application repositories (per app)

Each repo:

* Has its own Dockerfile and build pipeline.
* Pushes images tagged by commit SHA and optionally a stable channel tag (e.g., `prod`).

---

## 4. Terraform spec

### 4.1 Compute Engine VM

* Machine type: sized to workload (baseline 1 vCPU / 2–4 GB RAM).
* Boot disk: small (20–30 GB).
* Network: one NIC in default VPC (or dedicated VPC/subnet).
* External IP: static (recommended).
* Metadata:

  * `startup-script`: bootstrap script
  * parameters for:

    * stack repo URL (or GCS object path)
    * stack version/ref (e.g., a Git tag)
    * registry host/path
    * domain list (optional)
* OS Login: recommended for controlled SSH.
* Shielded VM: enabled by default.
* Automatic updates: handled via OS policy or your patching practice.

### 4.2 Persistent Disk

* Separate PD attached to VM.
* Mounted at `/mnt/pd`.
* Subdirectories:

  * `/mnt/pd/stack` (checked out stack repo or extracted bundle)
  * `/mnt/pd/data` (SQLite files, uploads, etc.)
  * `/mnt/pd/secrets` (only if you explicitly decide to store secrets here; generally prefer Secret Manager, but on a single VM you may accept a file-based approach with strict permissions)

### 4.3 Firewall rules

* Ingress allow:

  * tcp:22 from trusted source ranges (ideally your office/VPN IPs; avoid 0.0.0.0/0 if possible)
  * tcp:80,443 from 0.0.0.0/0
* Deny: everything else by default.
* No direct exposure of app container ports (containers bind to localhost/bridge network, proxied by reverse proxy only).

### 4.4 Optional: Service account / IAM

Two patterns:

* Minimal: no special permissions; CI deploys via SSH and registry is public/private with credentials.
* Recommended: VM SA can pull from Artifact Registry (read-only). CI uses SSH to trigger pull/update; VM uses its SA to authenticate pulls.

---

## 5. Startup script spec (bootstrap)

### 5.1 Idempotency

The startup script must be safe to run multiple times. It should:

* Check if Docker is installed; install if missing.
* Check disk mount; mount if not mounted.
* Fetch or update stack bundle.
* Run `docker compose up -d` to converge to desired state.

### 5.2 Steps (logical sequence)

1. **Install prerequisites**

* apt update
* install Docker Engine + Compose plugin
* install git/curl (as needed)

2. **Mount persistent disk**

* Create mount point `/mnt/pd`
* Format if brand-new (only on first run; must be guarded carefully)
* Add to `/etc/fstab` using disk UUID
* Mount

3. **Fetch stack definition**
   Choose one canonical approach:

**Approach A (Git clone)**

* Clone stack repo into `/mnt/pd/stack` if not present
* Otherwise `git fetch` + checkout configured ref/tag

**Approach B (GCS bundle)**

* Download tarball from GCS to `/mnt/pd/stack`
* Verify checksum/signature
* Extract

4. **Provision runtime configuration**

* Create per-site env files under `/mnt/pd/stack/env/`
* Create directories under `/mnt/pd/data/<service>/` for volumes
* Set correct permissions (non-root where possible)

5. **Start the reverse proxy + services**

* `docker compose pull` (optional; can be deferred to CI updates)
* `docker compose up -d`
* `docker image prune` with caution (never prune currently used images)

### 5.3 Failure behavior

* If bootstrap fails, script logs to:

  * `/var/log/startup-script.log` (or journal)
* It must not loop aggressively; it should exit non-zero and rely on operator intervention.

---

## 6. Container stack specification (Docker Compose)

### 6.1 Networking

* One internal Docker network, e.g., `web`.
* Reverse proxy attaches to `web` and routes to services by name.
* Services do not publish ports publicly except the proxy (80/443).

### 6.2 Volumes / persistence

* SQLite DB files stored on host path volume:

  * `/mnt/pd/data/site-a/db.sqlite`
* If you have backend hourly updater writing to DB:

  * either runs as a separate container sharing the same volume
  * or writes to a separate SQLite DB volume to avoid contention

### 6.3 Health checks

* Each service defines a health endpoint (e.g., `/healthz`).
* Compose healthcheck configured for basic monitoring.
* Reverse proxy should route only to healthy backends (proxy-dependent).

### 6.4 TLS and domains

Two recommended patterns:

* **Caddy** for automatic TLS via Let’s Encrypt (simplest ops).
* **Nginx** + certbot if you prefer explicit control.

The stack repo should encode:

* Domain → service mapping
* Default response headers (security headers, gzip/brotli, caching for static assets)

---

## 7. CI/CD specification (per app repo)

### 7.1 Trigger policy

* On push to `main` (or on release tags):

  * build/test
  * build image
  * push to registry with tags:

    * immutable: `:<git-sha>`
    * channel: `:prod` (optional but convenient)

### 7.2 Deployment mechanism

CI must update only the corresponding service, without restarting the entire stack.

Two common methods:

**Method A: Remote compose “pull + up”**

* CI SSHs to VM and runs:

  * `cd /mnt/pd/stack && docker compose pull site-a`
  * `docker compose up -d site-a`
* The compose file references image tags either:

  * stable tag `:prod` (CI updates tag in registry, VM just pulls latest), or
  * explicit SHA tag (requires editing a compose override file on VM)

**Method B: Compose override file update**

* CI uploads (scp) a `compose.override.yml` containing updated image tag for one service.
* Then runs `docker compose up -d site-a`.

**Recommendation:** start with **Method A + stable `:prod` tag** (simplest). If you need deterministic rollback, keep the SHA tags available and allow manual pinning.

### 7.3 Rollback procedure

* Identify last-known-good image tag (SHA).
* On VM:

  * either update override to pin `site-a:<sha>`
  * or retag `prod` back to that SHA and pull/restart

---

## 8. SQLite considerations (single VM, multiple services)

### 8.1 Single-writer policy

* If both frontend and hourly updater write to the same SQLite DB:

  * enforce WAL mode
  * keep write transactions short
  * avoid high concurrency
* If you can separate writes:

  * prefer separate DBs or separate write-service to reduce contention risk.

### 8.2 Backup policy

* Backup trigger: after hourly update (or nightly)
* Preferred method:

  * application-level SQLite backup command/API into a timestamped file
  * upload to GCS
* Keep at least N daily backups and M weekly backups.

---

## 9. Security baseline

### 9.1 SSH access

* Prefer OS Login and IAM-managed SSH.
* Otherwise: SSH keys restricted to CI and admins.
* Restrict SSH ingress source ranges if possible.

### 9.2 Secrets handling

Preferred: Google Secret Manager + retrieval at deploy time.
Acceptable (single VM, lower rigor): env files on PD with strict permissions and limited access.

### 9.3 Container runtime hardening

* Run containers as non-root when feasible.
* Drop Linux capabilities where feasible (later hardening).
* Keep reverse proxy as the only internet-facing container.

---

## 10. Observability and operations

### 10.1 Logs

* Use Docker logging driver (default json-file) with rotation.
* Optionally ship logs to Cloud Logging (later enhancement).

### 10.2 Metrics (optional but recommended)

* Node exporter + basic dashboards if you want visibility.
* At minimum: VM CPU/RAM/disk alerts.

### 10.3 Maintenance

* OS patch cadence: monthly (or according to your risk appetite).
* Docker updates: periodic.
* Disk space monitoring: alert at 70/85/95%.

---

## 11. Acceptance criteria

* A brand-new `terraform apply` produces a VM that, after boot:

  * has Docker/Compose installed
  * mounts PD at `/mnt/pd`
  * pulls stack definition
  * starts reverse proxy and at least one sample service
* A commit to app repo A:

  * builds and pushes image
  * updates only service A on the VM
  * does not restart service B
* SQLite data survives VM restarts and is stored on PD
* Backup artifacts are created and recoverable

---

## 12. Recommended defaults for your situation

* **Caddy** as reverse proxy if you want the least TLS friction.
* One PD (standard) for state; SSD only if you observe write latency issues.
* Stable image tag `:prod` for simplest deploy; keep SHA tags for rollback.