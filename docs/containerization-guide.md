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
- Expose your app port
- Health endpoint at `/health` (optional, recommended)

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
          --command="cd /mnt/pd/stack && sudo docker compose pull SERVICE_NAME && sudo docker compose up -d SERVICE_NAME"
```

Replace `SERVICE_NAME` with the name we give you.

## Setup Process

1. Send us the 5 fields above
2. We send you back: service name + `GCP_SA_KEY` (added to your repo)
3. You add the deploy job to your workflow
4. Push to main → auto-deploys
