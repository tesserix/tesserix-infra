# CI/CD Documentation

Tesserix uses GitHub Actions for all CI/CD automation. Reusable workflows live in
`tesserix-infra/.github/workflows/` (prefixed with `_`) and are called cross-repo
by all service repositories.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Reusable Workflows](#reusable-workflows)
- [Infrastructure Workflows](#infrastructure-workflows)
- [Service Pipeline Flows](#service-pipeline-flows)
- [Dependency Chain (go-shared)](#dependency-chain-go-shared)
- [Database Migrations](#database-migrations)
- [Cloudflare Worker Auto-Deploy](#cloudflare-worker-auto-deploy)
- [Secrets Reference](#secrets-reference)
- [Repository Setup Checklist](#repository-setup-checklist)
- [Common Operations](#common-operations)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
tesserix-infra (reusable workflows)
  _build-go.yml          ─── called by all Go service CI
  _build-nextjs.yml      ─── called by tesserix-home CI
  _release-go.yml        ─── called by all Go service releases
  _release-nextjs.yml    ─── called by tesserix-home release
  _deploy-cloudrun.yml   ─── called by all CI + release workflows
  _migrate-db.yml        ─── called by services with databases
  _cleanup-gar.yml       ─── called after every successful deploy
  _update-go-shared.yml  ─── called when go-shared releases a new version

  terraform.yml          ─── plan/apply on terraform/** changes
  cloudflare.yml         ─── deploy Cloudflare worker on changes or dispatch
  openfga.yml            ─── validate + deploy OpenFGA authorization models
```

### Key Design Decisions

- **Single environment**: Production only (no dev/staging split)
- **No org secrets**: GitHub Free plan doesn't propagate org secrets; all secrets are per-repo
- **`gcloud run services update`** instead of `gcloud run deploy`: Preserves Cloud SQL proxy sidecars
- **Conditional `--container` flag**: Only added when `container_name` input is provided (multi-container services)
- **WIF (Workload Identity Federation)**: Keyless auth from GitHub Actions to GCP; no service account keys stored
- **Auto-rollback**: Deploy workflow automatically rolls back to previous revision on smoke test failure

---

## Reusable Workflows

### `_build-go.yml` — Build Go Service

**Purpose**: Test, build Docker image, push to GHCR + GAR, run Trivy security scan.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name (used for image tagging) |
| `go_version` | no | `1.26` | Go version for tests |
| `run_tests` | no | `true` | Whether to run `go test` |
| `platforms` | no | `linux/amd64` | Docker build platforms |

| Secret | Required | Description |
|--------|----------|-------------|
| `GO_PRIVATE_TOKEN` | yes | GitHub PAT for `github.com/tesserix/*` private modules |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | yes | WIF provider resource name |
| `GCP_SERVICE_ACCOUNT` | yes | CI service account email |

| Output | Description |
|--------|-------------|
| `image` | Full GAR image URI (e.g., `asia-south1-docker.pkg.dev/tesserix/services/auth-bff:main-abc1234`) |
| `image_tag` | Image tag only |
| `digest` | Image digest (`sha256:...`) |

**Pipeline steps**: checkout → setup Go → configure private modules → `go vet` → `go test -race` → Docker build+push (GHCR + GAR) → Trivy scan → upload SARIF

---

### `_build-nextjs.yml` — Build Next.js App

**Purpose**: Lint, build Docker image, push to GHCR + GAR, run Trivy scan.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name |
| `node_version` | no | `22` | Node.js version |
| `platforms` | no | `linux/amd64` | Docker build platforms |
| `run_lint` | no | `true` | Whether to run ESLint |

| Secret | Required | Description |
|--------|----------|-------------|
| `PKG_READ_TOKEN` | no | npm private package token |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | yes | WIF provider |
| `GCP_SERVICE_ACCOUNT` | yes | CI service account |

| Output | Description |
|--------|-------------|
| `image` | Full GAR image URI |
| `image_tag` | Image tag only |
| `digest` | Image digest |

**Pipeline steps**: checkout → npm ci → eslint → Docker build+push → Trivy scan

---

### `_release-go.yml` — Release Go Service

**Purpose**: Quality checks, build release image, create GitHub Release with attestation.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name |
| `service_title` | yes | — | Human-readable name for release notes |
| `go_version` | no | `1.26` | Go version |
| `platforms` | no | `linux/amd64` | Docker build platforms |

| Output | Description |
|--------|-------------|
| `version` | Semver version (without `v` prefix) |
| `image` | Full GAR image URI |
| `digest` | Image digest |

**Pipeline steps**: `go vet` → `go test -race` → Docker build+push (multi-tag: latest, semver, major.minor) → Trivy scan → attestation → GitHub Release

**Triggered by**: Tag push matching `v*.*.*` or `workflow_dispatch` with tag input.

---

### `_release-nextjs.yml` — Release Next.js App

Same as `_release-go.yml` but for Next.js apps. Uses npm ci + ESLint instead of Go toolchain. Builds multi-arch (`linux/amd64,linux/arm64`) by default.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name |
| `service_title` | yes | — | Human-readable name |
| `node_version` | no | `22` | Node.js version |
| `platforms` | no | `linux/amd64,linux/arm64` | Docker build platforms |

---

### `_deploy-cloudrun.yml` — Deploy to Cloud Run

**Purpose**: Deploy image to Cloud Run, run smoke test, auto-rollback on failure, trigger Cloudflare update.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Cloud Run service name |
| `image` | yes | — | Full image URI with tag |
| `container_name` | no | `''` | Container name for multi-container (sidecar) services |
| `region` | no | `asia-south1` | GCP region |
| `project` | no | `tesserix` | GCP project ID |
| `environment` | no | `production` | GitHub Environment name |
| `health_path` | no | `/health` | Health check endpoint |

| Secret | Required | Description |
|--------|----------|-------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | yes | WIF provider |
| `GCP_SERVICE_ACCOUNT` | yes | CI service account |
| `DISPATCH_TOKEN` | no | PAT for Cloudflare dispatch (only auth-bff + tesserix-home) |

**Pipeline steps**:
1. **Deploy**: `gcloud run services update` (with `--container` flag if `container_name` is set)
2. **Smoke test**: 5 attempts, 10s intervals, using identity token auth against `health_path`
3. **Auto-rollback**: On failure, shifts 100% traffic to previous revision
4. **Cloudflare dispatch**: On success, sends `repository_dispatch` to tesserix-infra (if `DISPATCH_TOKEN` is set)

**Important**: Always uses `gcloud run services update` (never `gcloud run deploy`) to preserve Cloud SQL proxy sidecars.

#### Multi-container services (with Cloud SQL proxy sidecar)

These services pass `container_name` to target only the app container:
- `tickets-service`
- `subscription-service`
- `audit-service`

Services without `container_name` (no sidecar):
- `auth-bff`
- `tesserix-home`
- `feature-flags-service`
- `status-dashboard-service`
- `qr-service`

---

### `_migrate-db.yml` — Run Database Migrations

**Purpose**: Run golang-migrate against Cloud SQL via Cloud SQL Auth Proxy.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name (for logging) |
| `db_name` | yes | — | Database name (e.g., `tickets_db`) |
| `db_user` | yes | — | Database user (e.g., `tickets_user`) |
| `db_secret_name` | yes | — | Secret Manager secret name (e.g., `tickets-db-password`) |
| `migrations_path` | no | `migrations` | Path to migration files |
| `instance_connection_name` | no | `tesserix:asia-south1:tesserix-main` | Cloud SQL instance |
| `project` | no | `tesserix` | GCP project ID |

**Pipeline steps**:
1. Checkout (migration SQL files are in repo)
2. Authenticate to GCP via WIF
3. Install Cloud SQL Auth Proxy v2.14.3
4. Install golang-migrate v4.18.1
5. Fetch DB password from Secret Manager
6. Start Cloud SQL proxy (port 5432, waits for ready)
7. Run `migrate up`
8. Show current migration version

**Migration file format**: golang-migrate standard — `NNN_description.up.sql` / `NNN_description.down.sql`

---

### `_cleanup-gar.yml` — Cleanup Old GAR Images

**Purpose**: Delete old images from Artifact Registry, keep latest N.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name |
| `keep_count` | no | `5` | Number of latest images to keep |

---

### `_update-go-shared.yml` — Update go-shared Dependency

**Purpose**: Auto-update go-shared version in a service's go.mod/go.sum.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service_name` | yes | — | Service name (for commit message) |
| `version` | yes | — | go-shared version tag (e.g., `v1.3.1`) |

**Pipeline steps**: checkout → `go get go-shared@<version>` → `go mod tidy` → commit + push (if changed)

The push to main triggers the normal CI pipeline, which builds and deploys the service.

---

## Infrastructure Workflows

### `terraform.yml`

**Triggers**: Push to `main` or PR touching `terraform/**`

**Strategy**: Matrix of 4 stacks run sequentially (`max-parallel: 1`):
1. `01-foundation` — VPC, subnets, Cloud SQL networking
2. `02-core` — Cloud SQL instance, databases, secrets
3. `03-iam` — Service accounts, WIF, IAM bindings
4. `04-services` — Cloud Run services, Pub/Sub, Cloud Tasks

**Jobs**:
- `plan` — Runs on all PRs and pushes (parallel across stacks for speed)
- `apply` — Only on push to `main`, sequential, requires `production` GitHub Environment

Both use `-var-file=../terraform.tfvars` and remote state in `gs://tesserix-tf-state`.

---

### `cloudflare.yml`

**Triggers**:
- Push to `main` touching `cloudflare/**`
- `workflow_dispatch` (manual)
- `repository_dispatch` type `cloudrun-deployed` (from service deploys)

**What it does**: Resolves live Cloud Run URLs for auth-bff and tesserix-home via `gcloud`, then deploys the Cloudflare Worker with those URLs as `--var` arguments.

**Routes**:
- `tesserix.app/auth/*` → auth-bff
- `tesserix.app/*` → tesserix-home
- `{tenant}.tesserix.app` → storefront (future)

---

### `openfga.yml`

**Triggers**: Push to `main` touching `openfga/**`

**What it does**: Validates OpenFGA authorization models (platform + marketplace) using the FGA CLI, then deploys them to the OpenFGA server using a preshared key from Secret Manager.

---

## Service Pipeline Flows

### Go Services — CI (push to main)

```
push to main
  └─ build (_build-go.yml)
       ├─ go vet + go test -race
       ├─ Docker build + push (GHCR + GAR)
       └─ Trivy scan
  └─ migrate (_migrate-db.yml) [tickets-service, subscription-service only]
       ├─ Cloud SQL proxy start
       └─ golang-migrate up
  └─ deploy (_deploy-cloudrun.yml)
       ├─ gcloud run services update
       ├─ Smoke test (5 retries)
       ├─ Auto-rollback on failure
       └─ Cloudflare dispatch [auth-bff only]
  └─ cleanup (_cleanup-gar.yml)
       └─ Keep latest 5 images
```

### Go Services — Release (tag push)

```
tag v1.2.3
  └─ release (_release-go.yml)
       ├─ go vet + go test -race
       ├─ Docker build + push (multi-tag)
       ├─ Trivy scan + attestation
       └─ GitHub Release
  └─ migrate (_migrate-db.yml) [if applicable]
  └─ deploy (_deploy-cloudrun.yml)
  └─ cleanup (_cleanup-gar.yml)
```

### tesserix-home — CI (push to main)

```
push to main
  └─ build (_build-nextjs.yml)
       ├─ npm ci + eslint
       ├─ Docker build + push
       └─ Trivy scan
  └─ deploy (_deploy-cloudrun.yml)
       ├─ health_path: /api/health
       └─ Cloudflare dispatch
```

### tesserix-home — Release (tag push)

```
tag v1.2.3
  └─ release (_release-nextjs.yml)
       ├─ npm ci + eslint
       ├─ Docker build + push (multi-arch)
       ├─ Trivy scan + attestation
       └─ GitHub Release
  └─ deploy (_deploy-cloudrun.yml)
```

---

## Dependency Chain (go-shared)

When go-shared gets a new tag:

```
go-shared tag v1.4.0
  └─ release.yml
       ├─ go test ./... -race
       ├─ go build ./...
       └─ GitHub Release
  └─ notify-dependents (matrix: 6 repos)
       └─ repository_dispatch "go-shared-release" → { version: "v1.4.0" }

Each dependent repo receives the dispatch:
  └─ update-deps.yml
       └─ _update-go-shared.yml
            ├─ go get go-shared@v1.4.0
            ├─ go mod tidy
            └─ commit + push (if changed)
                 └─ triggers normal CI pipeline → build → deploy
```

**Dependent repos**: auth-bff, audit-service, tickets-service, feature-flags-service, subscription-service, qr-service

**Not dependent** (no go-shared import): tesserix-home, status-dashboard-service

---

## Database Migrations

### Services with automated migrations

| Service | DB Name | DB User | Secret | Migration Format |
|---------|---------|---------|--------|-----------------|
| tickets-service | `tickets_db` | `tickets_user` | `tickets-db-password` | golang-migrate (up/down SQL) |
| subscription-service | `subscriptions_db` | `subscriptions_user` | `subscriptions-db-password` | golang-migrate (up/down SQL) |

### Services with runtime migrations

| Service | Approach |
|---------|----------|
| audit-service | GORM `AutoMigrate` on each tenant DB connection (multi-tenant dynamic) |

### Adding a new migration

1. Create files in `migrations/` directory:
   ```
   migrations/
     005_add_new_column.up.sql
     005_add_new_column.down.sql
   ```

2. Push to main — the CI pipeline will:
   - Build the new image
   - Run `migrate up` (applies only new migrations)
   - Deploy the updated service

### Rolling back a migration

```bash
# Connect via Cloud SQL proxy locally
cloud-sql-proxy tesserix:asia-south1:tesserix-main --port 5432

# Run migrate down
migrate -path ./migrations \
  -database "postgres://tickets_user:<password>@localhost:5432/tickets_db?sslmode=disable" \
  down 1
```

---

## Cloudflare Worker Auto-Deploy

The Cloudflare Worker routes traffic based on hostname and path:

```
tesserix.app/auth/*  → auth-bff (Cloud Run)
tesserix.app/*       → tesserix-home (Cloud Run)
```

**Auto-deploy trigger**: When auth-bff or tesserix-home deploys successfully, the deploy workflow sends a `repository_dispatch` to tesserix-infra, which triggers `cloudflare.yml`. This resolves the latest Cloud Run URLs and redeploys the worker.

**Manual deploy**: `workflow_dispatch` on `cloudflare.yml` in tesserix-infra.

---

## Secrets Reference

### Per-repo secrets (required for all Go services)

| Secret | Description | Where to get it |
|--------|-------------|-----------------|
| `GO_PRIVATE_TOKEN` | GitHub PAT with `repo` scope | github.com → Settings → Developer settings → PATs |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | WIF provider resource name | `projects/677812215720/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | CI service account email | `sa-github-ci@tesserix.iam.gserviceaccount.com` |

### Additional secrets (specific repos)

| Secret | Repos | Description |
|--------|-------|-------------|
| `DISPATCH_TOKEN` | go-shared, auth-bff, tesserix-home | PAT with `repo` scope for cross-repo `repository_dispatch` |
| `PKG_READ_TOKEN` | tesserix-home | npm private package token (optional) |

### tesserix-infra repo variables (not secrets)

| Variable | Description |
|----------|-------------|
| `GCP_WIF_PROVIDER` | Same as `GCP_WORKLOAD_IDENTITY_PROVIDER` |
| `GCP_CI_SA` | Same as `GCP_SERVICE_ACCOUNT` |
| `TF_STATE_BUCKET` | `tesserix-tf-state` |

### Cloud SQL password secrets (in GCP Secret Manager)

| Secret ID | Database | Auto-generated by Terraform |
|-----------|----------|-----------------------------|
| `tickets-db-password` | `tickets_db` | yes |
| `subscriptions-db-password` | `subscriptions_db` | yes |
| `audit-db-password` | `audit_db` | yes |
| `openfga-db-password` | `openfga_db` | yes |
| `notifications-db-password` | `notifications_db` | yes |
| `tenants-db-password` | `tenants_db` | yes |
| `settings-db-password` | `settings_db` | yes |
| `documents-db-password` | `documents_db` | yes |

---

## Repository Setup Checklist

When adding a new Go service to the org:

### 1. Create workflows

Create `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main, 'feat/**', 'feature/**', 'bugfix/**', 'hotfix/**']
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  security-events: write
  id-token: write

jobs:
  build:
    uses: tesserix/tesserix-infra/.github/workflows/_build-go.yml@main
    with:
      service_name: <your-service-name>
    secrets:
      GO_PRIVATE_TOKEN: ${{ secrets.GO_PRIVATE_TOKEN }}
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}

  deploy:
    needs: [build]
    if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
    uses: tesserix/tesserix-infra/.github/workflows/_deploy-cloudrun.yml@main
    with:
      service_name: <your-service-name>
      image: ${{ needs.build.outputs.image }}
      container_name: <your-service-name>  # only if using Cloud SQL sidecar
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}

  cleanup:
    needs: [deploy]
    if: always() && needs.deploy.result == 'success'
    uses: tesserix/tesserix-infra/.github/workflows/_cleanup-gar.yml@main
    with:
      service_name: <your-service-name>
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

Create `.github/workflows/release.yml`:
```yaml
name: Release

on:
  push:
    tags: ['v*.*.*']
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag (e.g., v1.0.0)'
        required: true
        type: string

permissions:
  contents: write
  packages: write
  security-events: write
  attestations: write
  id-token: write

jobs:
  release:
    uses: tesserix/tesserix-infra/.github/workflows/_release-go.yml@main
    with:
      service_name: <your-service-name>
      service_title: <Your Service Title>
    secrets:
      GO_PRIVATE_TOKEN: ${{ secrets.GO_PRIVATE_TOKEN }}
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}

  deploy:
    needs: [release]
    uses: tesserix/tesserix-infra/.github/workflows/_deploy-cloudrun.yml@main
    with:
      service_name: <your-service-name>
      image: ${{ needs.release.outputs.image }}
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}

  cleanup:
    needs: [deploy]
    if: always() && needs.deploy.result == 'success'
    uses: tesserix/tesserix-infra/.github/workflows/_cleanup-gar.yml@main
    with:
      service_name: <your-service-name>
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

### 2. Add DB migration job (if service has a database)

Add between `build` and `deploy` in both `ci.yml` and `release.yml`:
```yaml
  migrate:
    needs: [build]  # or [release] in release.yml
    if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
    uses: tesserix/tesserix-infra/.github/workflows/_migrate-db.yml@main
    with:
      service_name: <your-service-name>
      db_name: <your_db>
      db_user: <your_user>
      db_secret_name: <your-db-password>
    secrets:
      GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
      GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

Update deploy to depend on migrate:
```yaml
  deploy:
    needs: [build, migrate]  # add migrate dependency
```

### 3. Add go-shared auto-update (if service depends on go-shared)

Create `.github/workflows/update-deps.yml`:
```yaml
name: Update go-shared

on:
  repository_dispatch:
    types: [go-shared-release]

permissions:
  contents: write

jobs:
  update:
    uses: tesserix/tesserix-infra/.github/workflows/_update-go-shared.yml@main
    with:
      service_name: <your-service-name>
      version: ${{ github.event.client_payload.version }}
    secrets:
      GO_PRIVATE_TOKEN: ${{ secrets.GO_PRIVATE_TOKEN }}
```

Then add the repo to go-shared's `release.yml` matrix.

### 4. Set repo secrets

```bash
gh secret set GO_PRIVATE_TOKEN -R tesserix/<repo-name>
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER -R tesserix/<repo-name>
gh secret set GCP_SERVICE_ACCOUNT -R tesserix/<repo-name>
# If it routes through Cloudflare:
gh secret set DISPATCH_TOKEN -R tesserix/<repo-name>
```

### 5. Ensure Dockerfile uses correct Go version

```dockerfile
FROM golang:1.26-alpine AS builder
```

### 6. Create Cloud Run service in Terraform

Add to `terraform/04-services/platform-services.tf` and apply.

---

## Common Operations

### Deploy a specific commit to production

```bash
# Push to main triggers CI automatically
git push origin main
```

### Create a release

```bash
git tag v1.2.3
git push origin v1.2.3
```

### Manually trigger a deployment

Go to the repo's Actions tab → select "CI" or "Release" → "Run workflow".

### Re-run a failed deploy

Go to Actions → find the failed run → click "Re-run failed jobs".

### Check deploy status

```bash
gcloud run services describe <service-name> \
  --region=asia-south1 --project=tesserix \
  --format="value(status.url)"
```

### View Cloud Run revisions

```bash
gcloud run revisions list --service=<service-name> \
  --region=asia-south1 --project=tesserix \
  --sort-by=~createTime --limit=5
```

### Manual rollback

```bash
gcloud run services update-traffic <service-name> \
  --region=asia-south1 --project=tesserix \
  --to-revisions=<revision-name>=100
```

### Run migrations manually

```bash
# Start proxy
cloud-sql-proxy tesserix:asia-south1:tesserix-main --port 5432 &

# Get password
gcloud secrets versions access latest --secret=tickets-db-password --project=tesserix

# Run
migrate -path ./migrations \
  -database "postgres://tickets_user:<password>@localhost:5432/tickets_db?sslmode=disable" \
  up
```

---

## Troubleshooting

### Build fails with "golang:1.26-alpine not found"

Ensure the Dockerfile uses the correct Go version. Current version: **Go 1.26**.

### Deploy succeeds but health check fails

1. Check the health endpoint: `curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" https://<service-url>/health`
2. Check Cloud Run logs: `gcloud run services logs read <service-name> --region=asia-south1 --project=tesserix --limit=50`
3. The deploy workflow auto-rolls back on health check failure.

### "Circuit breaker is open" / Cloud SQL proxy not ready

Services with Cloud SQL sidecar need retry logic for startup race conditions. Both tickets-service and subscription-service implement 5 retries with exponential backoff in their `InitDB()` functions.

### Migrations fail with "dirty database"

This means a previous migration partially applied. Fix:
```bash
migrate -path ./migrations \
  -database "postgres://..." \
  force <version>
```
Then re-run `migrate up`.

### `repository_dispatch` not triggering

1. Verify `DISPATCH_TOKEN` secret is set and the PAT has `repo` scope
2. Check that the target repo has the matching `repository_dispatch` type in its workflow
3. Token must belong to a user with write access to the target repo

### WIF authentication fails

1. Verify the WIF provider exists: `gcloud iam workload-identity-pools providers describe github-provider --location=global --workload-identity-pool=github-pool --project=tesserix`
2. Verify the SA has `roles/iam.workloadIdentityUser` with the correct `principalSet` for the repo
3. The current config allows all repos under the `tesserix` org

### Cloudflare worker not updating after deploy

1. Check if `DISPATCH_TOKEN` is set on the deploying repo
2. Check if `cloudflare.yml` in tesserix-infra received the dispatch (Actions tab)
3. Verify `CF_API_TOKEN` is set on tesserix-infra
4. Manually trigger: Actions → "Deploy Cloudflare Worker" → "Run workflow"
