# tesserix-infra

Infrastructure, CI/CD workflows, and platform configuration for the Tesserix platform.

## Repository Structure

```
tesserix-infra/
├── .github/workflows/       # GitHub Actions (reusable + infra-specific)
│   ├── _build-go.yml        # Reusable: build + test Go services
│   ├── _build-nextjs.yml    # Reusable: build + lint Next.js apps
│   ├── _release-go.yml      # Reusable: release Go services (tag → GitHub Release)
│   ├── _release-nextjs.yml  # Reusable: release Next.js apps
│   ├── _deploy-cloudrun.yml # Reusable: deploy to Cloud Run + smoke test + rollback
│   ├── _migrate-db.yml      # Reusable: run DB migrations via Cloud SQL proxy
│   ├── _cleanup-gar.yml     # Reusable: prune old Artifact Registry images
│   ├── _update-go-shared.yml# Reusable: auto-update go-shared in dependent repos
│   ├── terraform.yml        # Plan/apply Terraform on push
│   ├── cloudflare.yml       # Deploy Cloudflare edge worker
│   └── openfga.yml          # Validate + deploy OpenFGA authorization models
├── terraform/
│   ├── 01-foundation/       # VPC, subnets, Cloud SQL networking
│   ├── 02-core/             # Cloud SQL, databases, secrets, Pub/Sub
│   ├── 03-iam/              # Service accounts, WIF, IAM bindings
│   ├── 04-services/         # Cloud Run services, Cloud Tasks
│   ├── terraform.tfvars     # Shared variables (project, region, etc.)
│   └── Makefile             # Terraform helper commands
├── cloudflare/
│   ├── worker.js            # Edge router (routes by host + path)
│   └── wrangler.toml        # Cloudflare Worker config
├── openfga/
│   ├── model.fga            # Root model (shared types)
│   ├── platform/model.fga   # Platform authorization model
│   └── marketplace/model.fga# Marketplace authorization model
└── docs/
    └── ci-cd.md             # Comprehensive CI/CD documentation
```

## Stack

| Component | Service | Cost |
|-----------|---------|------|
| Compute | Cloud Run (scale to zero) | Pay per use |
| Database | Cloud SQL Postgres 15 (db-f1-micro, single instance) | ~$7/mo |
| Auth | Google Identity Platform + OpenFGA | $0 (free tier) |
| Messaging | Pub/Sub + Cloud Tasks | ~$0 |
| Edge routing | Cloudflare Worker | $0 (free tier) |
| Secrets | GCP Secret Manager | ~$0 |
| CI/CD | GitHub Actions | Free (2,000 min/mo) |
| **Total** | | **~$13-18/mo** |

## Services

| Service | Type | Database | Sidecar |
|---------|------|----------|---------|
| auth-bff | Go | none | no |
| tesserix-home | Next.js | none | no |
| tickets-service | Go | tickets_db | Cloud SQL proxy |
| subscription-service | Go | subscriptions_db | Cloud SQL proxy |
| audit-service | Go | audit_db | Cloud SQL proxy |
| feature-flags-service | Go | none | no |
| status-dashboard-service | Go | none | no |
| qr-service | Go | none | no |

## Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.9.0
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- [gh CLI](https://cli.github.com/) (for managing secrets)
- GCP project `tesserix` with billing enabled

## Getting Started

### 1. Terraform

```bash
cd terraform/01-foundation
terraform init \
  -backend-config="bucket=tesserix-tf-state" \
  -backend-config="prefix=01-foundation"
terraform plan -var-file=../terraform.tfvars
terraform apply -var-file=../terraform.tfvars
```

Stacks must be applied in order: `01-foundation` → `02-core` → `03-iam` → `04-services`.

On push to `main`, the `terraform.yml` workflow handles this automatically.

### 2. Secrets

Each service repo needs these GitHub secrets:

```bash
gh secret set GO_PRIVATE_TOKEN -R tesserix/<repo>        # GitHub PAT (repo scope)
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER -R tesserix/<repo>  # projects/677812215720/locations/global/workloadIdentityPools/github-pool/providers/github-provider
gh secret set GCP_SERVICE_ACCOUNT -R tesserix/<repo>     # sa-github-ci@tesserix.iam.gserviceaccount.com
```

For repos that trigger Cloudflare updates (auth-bff, tesserix-home):
```bash
gh secret set DISPATCH_TOKEN -R tesserix/<repo>           # GitHub PAT (repo scope)
```

### 3. Workflow sharing

Enable cross-repo workflow access:

**tesserix-infra** → Settings → Actions → General → Access → *"Accessible from repositories in the 'tesserix' organization"*

## CI/CD Pipelines

### Push to main (any service)
```
build + test → migrate DB (if applicable) → deploy Cloud Run → smoke test → cleanup images
                                             └─ auto-rollback on failure
```

### Tag release (any service)
```
build + test → security scan → GitHub Release → migrate DB → deploy → cleanup
```

### go-shared release
```
tag → test → release → dispatch to 6 repos → auto-update go.mod → triggers CI
```

### Infrastructure changes
```
terraform/** push → plan all stacks → apply sequentially (on main)
cloudflare/** push → deploy Cloudflare Worker
openfga/** push   → validate + deploy authorization models
```

Full documentation: **[docs/ci-cd.md](docs/ci-cd.md)**

## Terraform Stacks

| Stack | Purpose | Key Resources |
|-------|---------|---------------|
| `01-foundation` | Networking | VPC, subnets, Cloud NAT, private service networking |
| `02-core` | Data layer | Cloud SQL instance, 18 databases, per-service users + passwords, Pub/Sub topics, Secret Manager |
| `03-iam` | Identity | Service accounts per service, WIF pool + provider, IAM bindings |
| `04-services` | Compute | Cloud Run services, Cloud Tasks queues, environment variables, service-to-service bindings |

State is stored in `gs://tesserix-tf-state` with per-stack prefixes.

## Authorization (OpenFGA)

Two authorization models, one per product:

- **Platform** (`openfga/platform/model.fga`): Admin roles, tenant management, system settings
- **Marketplace** (`openfga/marketplace/model.fga`): Vendor/customer roles, product/order access

Both deploy automatically on push to `openfga/**`.

## Cloudflare Worker

Edge routing at `tesserix.app`:

| Pattern | Target |
|---------|--------|
| `tesserix.app/auth/*` | auth-bff (Cloud Run) |
| `tesserix.app/*` | tesserix-home (Cloud Run) |
| `{tenant}.tesserix.app` | Storefront (future) |

Auto-deploys when auth-bff or tesserix-home deploys (via `repository_dispatch`), or when `cloudflare/**` files change.
