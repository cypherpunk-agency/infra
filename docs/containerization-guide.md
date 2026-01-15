# Deploying to Our Infrastructure

## What We Need From You

| Field | Example | Required |
|-------|---------|----------|
| Image | `ghcr.io/your-org/your-repo:prod` | Yes |
| Port | `3000` | Yes |
| Domain | `myapp.example.com` | Yes |
| Secrets | `DATABASE_URL`, `API_KEY` | If any |
| Storage | `/app/data` | If any |

## Image Requirements

- Push to `ghcr.io` with `:prod` tag on main branch
- **Make the package public** (required for our server to pull it)
- Expose your app port
- Health endpoint at `/health` (optional, recommended)

### Making Your Package Public

After your first image push, the package will be private by default. To make it public:

1. Go to your GitHub org
2. Click **Packages**
3. Click your package name
4. Click **Package settings** (right sidebar)
5. Scroll to **Danger Zone**
6. Click **Change visibility** → Select **Public** → Confirm

## Security Best Practices

### 1. Scan Your Images

Before deploying, scan your images for vulnerabilities:

```bash
# Using Trivy (recommended)
trivy image ghcr.io/your-org/your-repo:prod

# Fix any HIGH or CRITICAL vulnerabilities before deploying
```

### 2. Don't Store Secrets in Images

**Never** bake secrets into your Docker image:
- ❌ No hardcoded API keys
- ❌ No database passwords in Dockerfile
- ❌ No `.env` files in image

Instead:
- ✅ Use environment variables (we provide via secrets)
- ✅ Request secrets during onboarding
- ✅ Keep secrets separate from code

### 3. Use Official Base Images

Use official images from trusted sources:
```dockerfile
# Good
FROM node:20-alpine
FROM python:3.12-slim

# Avoid
FROM random-user/node  # Unknown source
```

### 4. Run as Non-Root User

Create and use a non-root user in your Dockerfile:

```dockerfile
# Create user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Switch to user
USER appuser

# Your app runs as appuser, not root
CMD ["node", "server.js"]
```

### 5. Keep Dependencies Updated

Regularly update your dependencies to get security patches:

```bash
# Node.js
npm audit
npm audit fix

# Python
pip list --outdated
pip install --upgrade package-name

# Run these regularly!
```

### 6. Define Resource Limits

We'll add resource limits to prevent your service from exhausting VM resources, but you can help by:
- Testing your app's memory usage under load
- Reporting expected resource needs (helps us set appropriate limits)
- Optimizing memory leaks before deploying

### 7. Implement Health Checks

Add a `/health` or `/healthz` endpoint:

```javascript
// Express example
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});
```

This helps us:
- Detect when your service is unhealthy
- Restart automatically if needed
- Monitor uptime

### 8. Keep Secrets Secure Locally

**Never commit the GCP service account key to git!**

Add to your `.gitignore`:
```
*-key.json
*.json
```

Use a secure password manager to store the key.

## Add to Your Workflow

After we configure your service, add this deploy job:

```yaml
deploy:
  needs: build  # or whatever your build job is called
  runs-on: ubuntu-latest
  steps:
    - uses: google-github-actions/auth@v2
      with:
        credentials_json: ${{ secrets.GCP_SA_KEY }}

    - uses: google-github-actions/setup-gcloud@v2

    - name: Deploy
      run: |
        gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
          --command="sudo /usr/local/bin/deploy-service SERVICE_NAME"
```

Replace `SERVICE_NAME` with the name we give you.

## Setup Process

1. Send us the 5 fields above
2. We send you back:
   - Your **service name**
   - A **GCP service account key file** (JSON)
3. You:
   - Add the key to GitHub as `GCP_SA_KEY` secret
   - Add the deploy job to your workflow
4. Push to main → auto-deploys

## What You Get

The service account key gives you:
- **Deploy access** - trigger deployments from CI/CD
- **Status access** - check if your container is running/healthy
- **Log access** - view your container logs
- **Shell access** - exec into your container for debugging

You can only access your own service, not others.

## Local Setup (Optional)

To use the key locally for debugging:

```bash
# Authenticate with gcloud
gcloud auth activate-service-account --key-file=path/to/your-key.json

# Set project
gcloud config set project cyberphunk-agency
```

## Accessing Your Service

Check status:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo /usr/local/bin/service-status SERVICE_NAME"
```

View logs:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo /usr/local/bin/service-logs SERVICE_NAME 100"
```

Shell into container:
```bash
gcloud compute ssh web-server --zone=us-central1-a --tunnel-through-iap \
  --command="sudo /usr/local/bin/service-shell SERVICE_NAME"
```

Replace `SERVICE_NAME` with the name we gave you.
