# Infrastructure Cost Analysis: GKE vs Cloud Run

> **Date:** March 2026
> **Old Project:** `tesseracthub-480811` (GKE, asia-south1)
> **New Project:** `tesserix` (Cloud Run, asia-south1)
> **Region:** asia-south1 (Mumbai)

---

## Executive Summary

| Metric | Old (GKE) | New (Cloud Run) | Change |
|---|---|---|---|
| **Monthly cost** | ~$275-350 | ~$13-18 | **-93% to -95%** |
| **Annual cost** | ~$3,300-4,200 | ~$156-216 | **~$3,100-4,000 saved/yr** |
| **Always-on compute** | 3 nodes (12 vCPU, 48 Gi) | 0 (scale to zero) | -100% |
| **Managed components** | 8+ | 3 | -63% |
| **Deployment complexity** | Helm + ArgoCD + Istio | `gcloud run deploy` | Drastically simpler |

---

## 1. Old Infrastructure: GKE (project `tesseracthub-480811`)

### 1.1 GKE Cluster

| Resource | Specification | Est. Monthly Cost |
|---|---|---|
| GKE cluster (Standard) | 1x control plane | $0 (free tier) or $74.40 |
| Node pool (3x e2-standard-4) | 12 vCPU, 48 Gi RAM total | $180-250 |
| Persistent disks (~29 Gi) | SSD + Standard PDs | $5-10 |
| **Subtotal: Cluster** | | **$185-334** |

### 1.2 In-Cluster Workloads (running on the GKE nodes)

All of the following ran inside the GKE cluster, consuming the node pool capacity:

#### Application Services

| Service | Replicas | CPU Request | Memory Request |
|---|---|---|---|
| auth-bff | 2 | 1000m | 512Mi |
| audit-service | 1 | 250m | 256Mi |
| tickets-service | 1 | 250m | 256Mi |
| feature-flags-service | 1 | 100m | 128Mi |
| status-dashboard-service | 1 | 100m | 128Mi |
| tesserix-home | 1 | 250m | 256Mi |
| **App subtotal** | **7 pods** | **~1,950m** | **~1,536Mi** |

#### Third-Party Infrastructure (in-cluster)

| Component | Pods | CPU | Memory | Storage |
|---|---|---|---|---|
| Keycloak | 3 | 3,000m | 6 Gi | - |
| Keycloak Redis Sentinel | 6 | 600m | 1.5 Gi | - |
| NATS | 3 | 1,500m | 1.5 Gi | 20 Gi PVC |
| Redis (tesserix) | 1 | 100m | 512Mi | 5 Gi PVC |
| Redis (marketplace) | 1 | 100m | 512Mi | 5 Gi PVC |
| PostgreSQL (global) | 1 | 500m | 1 Gi | 10 Gi PVC |
| PostgreSQL (marketplace) | 1 | 500m | 1 Gi | 10 Gi PVC |
| ArgoCD (all components) | ~5 | 500m | 1 Gi | - |
| Istio (control plane + proxies) | ~3 + sidecars | 500m + sidecars | 1 Gi + sidecars | - |
| External Secrets Operator | 1 | 100m | 128Mi | - |
| **Infra subtotal** | **~25 pods** | **~7,400m** | **~14.6 Gi** | **~50 Gi** |

**Total in-cluster:** ~32 pods consuming ~9.35 vCPU and ~16 Gi RAM baseline.

### 1.3 External GCP Services

| Service | Specification | Est. Monthly Cost |
|---|---|---|
| GCP Network Load Balancer | Istio IngressGateway | $18.26 |
| Artifact Registry | Container images | $1-2 |
| Secret Manager | ~10 secrets | $0.30 |
| Cloud DNS (if used) | Hosted zone | $0.20 |
| **Subtotal: External** | | **~$20-21** |

### 1.4 Operational Overhead

| Component | Operational Burden |
|---|---|
| Keycloak | Realm management, upgrades, Infinispan cache tuning, Redis Sentinel config |
| Istio | VirtualService/Gateway YAML, mTLS debugging, proxy resource overhead, version upgrades |
| ArgoCD | Application CRDs, sync management, RBAC, Git repo credentials |
| NATS | Cluster management, JetStream config, consumer management |
| Redis x2 | Persistence config, memory tuning, failover (no HA) |
| PostgreSQL x2 | Backup scripts, no PITR, manual failover, vacuum tuning |
| ESO | ClusterSecretStore CRDs, GCP SA key rotation |
| Helm Charts | Chart.yaml dependencies, values-prod.yaml per service, template debugging |
| Node Management | OS patches, node pool upgrades, capacity planning |

### 1.5 Total Old Infrastructure Cost

| Category | Monthly Cost |
|---|---|
| GKE nodes (3x e2-standard-4) | $180-250 |
| GKE management fee | $0-74 |
| Persistent disks (50 Gi) | $5-10 |
| Load balancer | $18 |
| Artifact Registry | $1-2 |
| Secret Manager | $0.30 |
| **TOTAL** | **$204-354/month** |

---

## 2. New Infrastructure: Cloud Run (project `tesserix`)

### 2.1 Deployed Services (17 currently live)

| Service | CPU | Memory | Min Instances | Max Instances | Sidecar |
|---|---|---|---|---|---|
| analytics-service | 1 | 256Mi | 0 | 3 | cloud-sql-proxy |
| audit-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| auth-bff | 1 | 256Mi | 0 | 10 | - |
| document-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| feature-flags-service | 1 | 256Mi | 0 | 3 | - |
| location-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| marketplace-onboarding | 1 | 512Mi | 0 | 5 | cloud-sql-proxy |
| notification-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| openfga | 1 | 512Mi | 0 | 5 | cloud-sql-proxy |
| qr-service | 1 | 256Mi | 0 | 3 | - |
| status-service | 1 | 256Mi | 0 | 2 | - |
| subscription-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| tenant-router-service | 1 | 256Mi | 0 | 3 | cloud-sql-proxy |
| tenant-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| tesserix-home | 1 | 512Mi | 0 | 5 | - |
| tickets-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |
| verification-service | 1 | 256Mi | 0 | 5 | cloud-sql-proxy |

**All services scale to zero.** No cost when idle.

### 2.2 Cloud Run Free Tier (per month)

| Resource | Free Allowance | Our Usage | Within Free Tier? |
|---|---|---|---|
| Requests | 2 million | Low (pre-launch) | Yes |
| vCPU-seconds | 180,000 | Minimal | Yes |
| Memory GiB-seconds | 360,000 | Minimal | Yes |
| Networking (egress) | 1 GiB to N. America | Minimal | Yes |

**Estimated Cloud Run compute cost: $0-5/month** (mostly free tier at current traffic).

### 2.3 Cloud SQL

| Parameter | Value |
|---|---|
| Instance | `tesserix-main` |
| Engine | PostgreSQL 15 |
| Tier | `db-f1-micro` (shared vCPU, 0.6 Gi RAM) |
| Disk | 10 Gi SSD |
| Availability | Zonal (no HA) |
| Backups | Enabled, PITR, 7-day retention |
| Region | asia-south1 |

**Cost: ~$7.67/month** (db-f1-micro asia-south1 pricing)

Hosts databases for: audit, tickets, subscriptions, tenants, notifications, documents, locations, analytics, verifications, openfga, marketplace-onboarding, tenant-router.

### 2.4 Google Pub/Sub

| Topics (10) | Subscriptions (2 active) |
|---|---|
| tesserix-audit-events | audit-service-push |
| tesserix-audit-events-dlq | notification-service-push |
| tesserix-ticket-events | |
| tesserix-ticket-events-dlq | |
| tesserix-subscription-events | |
| tesserix-notification-events | |
| tesserix-notification-events-dlq | |
| prod-email-queue | |
| prod-sms-queue | |
| prod-push-queue | |

**Cost: $0/month** (free tier: 10 GiB/month throughput)

### 2.5 Google Identity Platform (replaces Keycloak)

| Feature | Details |
|---|---|
| Auth method | OIDC (Google Sign-In) |
| Tenants | `staff` + `customer` (2 GIP tenants) |
| MAU | < 50 |
| Pricing tier | Free (up to 50K MAU) |

**Cost: $0/month**

Replaced: Keycloak (3 pods, 3 CPU, 6 Gi) + Redis Sentinel (6 pods).

### 2.6 OpenFGA on Cloud Run (replaces Keycloak realm RBAC)

Runs as a Cloud Run service with scale-to-zero. Uses Cloud SQL for persistence.

**Cost: included in Cloud Run free tier**

### 2.7 Cloudflare (replaces GCP Load Balancer + Istio Gateway)

| Component | Details | Cost |
|---|---|---|
| Worker (`tesserix-router`) | Routes tesserix.app + mark8ly.com | $0 (100K req/day free) |
| DNS (tesserix.app) | Proxied CNAME records | $0 |
| DNS (mark8ly.com) | Proxied CNAME records | $0 |
| KV (TENANT_ROUTES) | Tenant slug routing | $0 (free tier) |
| SSL | Universal SSL | $0 |

**Cost: $0/month** (replaces $18.26/month GCP LB)

### 2.8 Other GCP Services

| Service | Details | Est. Monthly Cost |
|---|---|---|
| Secret Manager | ~36 secrets, ~6 versions each | $0.54 |
| GCS | 5 buckets (assets, backups, tf-state, public, cloudbuild) | $0.50-1.00 |
| Artifact Registry | Container images for 17 services | $1-2 |
| Cloud Tasks | Ticket task processing | $0 (free tier) |

### 2.9 Auth Architecture Comparison

| Aspect | Old (Keycloak) | New (GIP + OpenFGA) |
|---|---|---|
| Identity provider | Keycloak (self-hosted, 9 pods) | Google Identity Platform (managed) |
| Session storage | Redis (2 pods, 10 Gi PVCs) | Encrypted JWT cookies (stateless) |
| Authorization | Keycloak realm roles | OpenFGA (Cloud Run, scale-to-zero) |
| Multi-tenancy | Keycloak realms | GIP tenants + OpenFGA stores |
| Cost | ~$80-120/month (compute) | $0/month |
| Ops burden | High (upgrades, cache tuning, HA) | Zero (fully managed + serverless) |

### 2.10 Total New Infrastructure Cost

| Category | Monthly Cost |
|---|---|
| Cloud Run (17 services, scale-to-zero) | $0-5 |
| Cloud SQL (db-f1-micro, 10 Gi SSD) | $7.67 |
| Pub/Sub (10 topics, 2 subscriptions) | $0 |
| Identity Platform | $0 |
| Cloudflare Worker + DNS | $0 |
| Secret Manager (~36 secrets) | $0.54 |
| GCS (5 buckets) | $0.50-1.00 |
| Artifact Registry | $1-2 |
| Cloud Tasks | $0 |
| **TOTAL** | **$10-16/month** |

---

## 3. Component-by-Component Migration Map

| Old Component | Pods | CPU | RAM | New Replacement | New Cost |
|---|---|---|---|---|---|
| GKE nodes (3x e2-standard-4) | - | 12 vCPU | 48 Gi | Cloud Run (scale-to-zero) | $0-5 |
| Keycloak | 3 | 3,000m | 6 Gi | Google Identity Platform | $0 |
| Keycloak Redis Sentinel | 6 | 600m | 1.5 Gi | *eliminated* (no cache needed) | $0 |
| NATS | 3 | 1,500m | 1.5 Gi | Google Pub/Sub | $0 |
| Redis (sessions) | 1 | 100m | 512Mi | Encrypted JWT cookies | $0 |
| Redis (cache) | 1 | 100m | 512Mi | In-memory TTL store | $0 |
| PostgreSQL (2x StatefulSet) | 2 | 1,000m | 2 Gi | Cloud SQL db-f1-micro | $7.67 |
| Istio (mesh + sidecars) | 3+ | 500m+ | 1 Gi+ | go-shared middleware | $0 |
| ArgoCD | 5 | 500m | 1 Gi | GitHub Actions | $0 |
| External Secrets Operator | 1 | 100m | 128Mi | Cloud Run native secrets | $0 |
| GCP Load Balancer | - | - | - | Cloudflare Worker | $0 |
| Helm charts (30+ templates) | - | - | - | Terraform (4 stacks) | $0 |
| **TOTAL** | **~32 pods** | **~9.4 vCPU** | **~16 Gi** | | **~$8-13** |

---

## 4. Architecture Diagrams

### 4.1 Old Architecture (GKE)

```
Internet
  |
Cloudflare (DNS only)
  |
GCP Network Load Balancer ($18/mo)
  |
Istio IngressGateway (GKE)
  |
  +-- VirtualService routing
  |
  +-- auth-bff (2 pods) -----> Redis (sessions)
  |                        +--> Keycloak (3 pods) --> Keycloak Redis (6 pods)
  |                        +--> NATS (publish)
  |
  +-- audit-service (1 pod) --> PostgreSQL (StatefulSet) + Redis (cache)
  |                         <-- NATS (subscribe)
  |
  +-- tickets-service (1 pod) -> PostgreSQL (StatefulSet)
  |                           <-- NATS (subscribe)
  |
  +-- feature-flags-service (1 pod)
  +-- status-dashboard-service (1 pod)
  +-- tesserix-home (1 pod)
  |
  ArgoCD (5 pods) -- syncs Helm charts from Git
  ESO (1 pod) -- syncs secrets from GCP Secret Manager

GKE Cluster: 3x e2-standard-4 nodes
Total: ~32 pods, 12 vCPU, 48 Gi RAM provisioned
Cost: ~$275-350/month
```

### 4.2 New Architecture (Cloud Run)

```
Internet
  |
Cloudflare Worker ($0) -- tesserix-router
  |-- tesserix.app/auth/* --> auth-bff (Cloud Run, scale-to-zero)
  |-- tesserix.app/*      --> tesserix-home (Cloud Run, scale-to-zero)
  |-- *.mark8ly.com/*     --> tenant routing via KV
  |
  auth-bff -----> GIP (managed, $0) for OIDC
             +--> OpenFGA (Cloud Run) for authz
             +--> Pub/Sub (publish audit events, $0)
             +--> Encrypted JWT cookies (no Redis)
  |
  audit-service <-- Pub/Sub push ($0) --> Cloud SQL ($7.67)
  tickets-service <-- Cloud Tasks ($0) --> Cloud SQL
  notification-service <-- Pub/Sub push --> Cloud SQL + SendGrid
  tenant-service --> Cloud SQL
  subscription-service --> Cloud SQL + Stripe
  [... 11 more services, all scale-to-zero ...]
  |
  Cloud SQL (single db-f1-micro, 12 databases, per-service users)
  Secret Manager (36 secrets, native Cloud Run integration)
  GCS (5 buckets, multi-tenant path isolation)

Cloud Run: 17 services, ALL scale to zero
Total: 0 always-on compute
Cost: ~$13-18/month
```

---

## 5. Operational Complexity Comparison

| Dimension | Old (GKE) | New (Cloud Run) |
|---|---|---|
| **Deployment** | Helm chart update -> ArgoCD sync -> rollout | `gcloud run services update` (1 command) |
| **Scaling** | HPA + node autoscaler config | Automatic (0 to max, per-service) |
| **Secrets** | ESO -> ClusterSecretStore -> ExternalSecret CRD | Native Cloud Run secret refs |
| **TLS/mTLS** | Istio auto-mTLS + cert-manager | Cloud Run native HTTPS + OIDC tokens |
| **Routing** | Istio VirtualService + Gateway YAML | Cloudflare Worker (140 lines JS) |
| **Database** | Self-managed StatefulSets, no HA, manual backups | Cloud SQL managed, PITR, auto-backups |
| **Messaging** | NATS cluster (3 pods, JetStream config) | Pub/Sub push (managed, auto-retry, DLQ) |
| **Auth infra** | Keycloak + Redis Sentinel (9 pods to manage) | GIP (zero ops, Google-managed) |
| **Monitoring** | Prometheus + Grafana (self-hosted) | Cloud Monitoring + Logging (built-in) |
| **Node patching** | Manual or auto-upgrade windows | N/A (serverless) |
| **CI/CD pipeline** | Build -> push -> update Helm values -> ArgoCD sync | Build -> push -> `gcloud run deploy` |
| **Infra-as-code** | Helm charts (30+ templates) + K8s manifests | Terraform (4 stacks, ~20 files) |
| **Repo structure** | tesserix-k8s (charts/, argocd/, manifests/) | tesserix-infra (terraform/, cloudflare/) |
| **Go shared lib updates** | Manual go.mod bump in each repo | Automated via `repository_dispatch` |

---

## 6. Risk & Tradeoff Analysis

### 6.1 What We Gained

| Benefit | Details |
|---|---|
| **95% cost reduction** | $275-350 -> $13-18/month |
| **Zero idle cost** | All services scale to zero when unused |
| **No node management** | No OS patches, no capacity planning, no node pool upgrades |
| **Managed database** | Auto-backups, PITR, no manual vacuum tuning |
| **Managed auth** | GIP handles user management, MFA, account recovery |
| **Simpler deployments** | 1 command deploys, no Helm/ArgoCD/Istio debugging |
| **Faster cold starts** | Go services: ~200-500ms, Next.js: ~1-2s |
| **Built-in observability** | Cloud Logging, Cloud Trace, Error Reporting included |

### 6.2 Tradeoffs Accepted

| Tradeoff | Mitigation |
|---|---|
| **Cold starts** | Go services start in <500ms; acceptable for current traffic |
| **No server-side session invalidation** | Short-lived JWTs (15 min) + refresh tokens; revocation list via Firestore if needed |
| **Single Cloud SQL instance** | Sufficient for current load; can upgrade tier or add read replicas later |
| **No service mesh** | go-shared middleware handles auth context; Cloud Run OIDC for service-to-service |
| **Vendor lock-in (GCP)** | All services are standard Docker containers; portable to any platform |
| **db-f1-micro limitations** | 0.6 Gi RAM, shared vCPU; upgrade to db-g1-small ($25/mo) if needed |

### 6.3 When to Scale Back to GKE

| Trigger | Action |
|---|---|
| Cloud Run costs exceed ~$200/month | Evaluate GKE Autopilot for hot-path services |
| Need persistent WebSocket connections | Move specific services to GKE or Cloud Run with session affinity |
| Database needs exceed db-f1-micro | Upgrade Cloud SQL tier (db-g1-small: ~$25/mo, db-custom-1-3840: ~$50/mo) |
| >10M requests/month sustained | Hybrid: keep low-traffic services on Cloud Run, move hot paths to GKE |

---

## 7. Logging, Monitoring & Observability Costs

Cloud Run includes a comprehensive observability stack at **$0/month** at current usage levels.

### 7.1 Current Configuration

| Component | Configuration | Details |
|---|---|---|
| `_Required` log bucket | 400-day retention (mandatory) | Admin activity, system events, access transparency logs |
| `_Default` log bucket | 30-day retention | All Cloud Run application logs, request logs |
| Log sinks | 2 (default GCP sinks) | No custom exports to BigQuery/GCS/Pub/Sub |
| Custom log metrics | None | Using built-in platform metrics only |
| Alerting policies | None | No custom alerts configured |
| Custom dashboards | None | Using Cloud Run default dashboard |
| Enabled services | Cloud Logging, Cloud Monitoring, Cloud Trace | All enabled, all within free tier |

### 7.2 Free Tier Coverage

| Service | Free Allowance | Estimated Usage | Headroom |
|---|---|---|---|
| **Cloud Logging** (ingestion) | 50 GiB/month | < 1 GiB (17 services, scale-to-zero) | ~98% unused |
| **Cloud Logging** (storage) | 30-day `_Default` + 400-day `_Required` | Included free | N/A |
| **Cloud Monitoring** (platform metrics) | Always free | Request count, latency, error rate, CPU, memory, instance count | Unlimited |
| **Cloud Monitoring** (alerting) | 500 policies | 0 configured | 500 remaining |
| **Cloud Trace** | 2.5M spans/month | < 10K spans | ~99.6% unused |
| **Error Reporting** | Always free | Automatic from stderr logs | Unlimited |

**Total observability cost: $0.00/month**

### 7.3 What's Included for Free (per Cloud Run service)

Built-in platform metrics (no setup required):

- Request count (by response code)
- Request latency (p50, p95, p99)
- Container CPU utilization
- Container memory utilization
- Active instance count
- Billable instance time
- Startup latency
- Request concurrency

Built-in logging:

- Stdout/stderr captured automatically
- Structured JSON logs supported (Go `slog` / `zerolog`)
- Request logs with trace ID, latency, status code
- Container lifecycle events (start, shutdown)

### 7.4 Comparison with Old GKE Observability

| Aspect | Old (GKE) | New (Cloud Run) | Cost Difference |
|---|---|---|---|
| **Log collection** | Fluentd/Fluentbit DaemonSet on each node | Built-in, automatic | Same ($0 at low volume) |
| **Metrics** | Prometheus + Grafana (self-hosted, ~2 pods) | Cloud Monitoring (managed) | Saved ~200m CPU, 512Mi RAM |
| **Tracing** | Jaeger or manual (if configured) | Cloud Trace (automatic) | $0 both |
| **Dashboards** | Grafana (self-hosted) | Cloud Console (managed) | Saved 1 pod |
| **Alerting** | Alertmanager (self-hosted) | Cloud Monitoring alerting | Saved 1 pod |
| **Istio metrics** | Envoy proxy metrics, Kiali dashboard | N/A (no mesh) | Saved sidecar overhead |
| **Total ops burden** | 3-4 monitoring pods to manage | Zero (fully managed) | |

### 7.5 Cost Escalation Thresholds

| Trigger | Volume | Additional Cost |
|---|---|---|
| Log ingestion > 50 GiB/month | ~100M log lines (500 bytes avg) | $0.50/GiB over free tier |
| Extended log retention > 30 days | Change `_Default` bucket config | $0.01/GiB/month stored |
| Custom/user-defined metrics | Prometheus or OpenTelemetry export | $0.258 per 1,000 time series/month |
| Cloud Trace > 2.5M spans/month | ~2.5M+ requests with tracing | $0.20 per million spans |
| Log routing to BigQuery/GCS | Custom sink for analytics | BigQuery: $5/TiB queried; GCS: $0.02/GiB stored |
| Uptime checks > free tier | External health checks | $0.30 per 1,000 executions |

### 7.6 Estimated Cost at Scale

| Traffic Level | Log Volume | Monitoring Cost |
|---|---|---|
| Current (pre-launch) | < 1 GiB/month | **$0** |
| 100K requests/month | ~2-5 GiB/month | **$0** (within free tier) |
| 1M requests/month | ~10-20 GiB/month | **$0** (within free tier) |
| 10M requests/month | ~50-100 GiB/month | **$0-25** (may exceed free tier) |
| 100M requests/month | ~500 GiB-1 TiB/month | **$225-475** (consider log exclusion filters) |

> **Recommendation:** At 10M+ requests/month, add log exclusion filters to drop verbose health check and static asset logs. This can reduce ingestion volume by 30-60%.

---

## 8. Logging & Monitoring in Cost Tables

### Minimum Viable Cost (current state, low traffic)

| Component | Cost |
|---|---|
| Cloud SQL (db-f1-micro) | $7.67 |
| Cloud Run (free tier) | $0.00 |
| Logging & Monitoring (free tier) | $0.00 |
| Pub/Sub (free tier) | $0.00 |
| Identity Platform (free tier) | $0.00 |
| Cloudflare (free tier) | $0.00 |
| Secret Manager | $0.54 |
| GCS | $0.75 |
| Artifact Registry | $1.50 |
| **Monthly Total** | **$10.46** |
| **Annual Total** | **$125.52** |

### Realistic Estimate (with light usage spikes)

| Component | Cost |
|---|---|
| Cloud SQL (db-f1-micro) | $7.67 |
| Cloud Run (light traffic) | $3-5 |
| Logging & Monitoring (free tier) | $0 |
| Pub/Sub | $0 |
| Identity Platform | $0 |
| Cloudflare | $0 |
| Secret Manager | $0.54 |
| GCS | $1.00 |
| Artifact Registry | $2.00 |
| **Monthly Total** | **$14-16** |
| **Annual Total** | **$168-192** |

### Previous GKE Cost

| Component | Cost |
|---|---|
| GKE cluster + nodes | $180-324 |
| Load Balancer | $18.26 |
| Persistent Disks | $5-10 |
| Artifact Registry | $1-2 |
| Secret Manager | $0.30 |
| **Monthly Total** | **$204-354** |
| **Annual Total** | **$2,448-4,248** |

---

## 9. Savings Projection (12 months)

```
Old annual cost (avg):  $3,348  ($279/month average)
New annual cost (avg):  $  180  ($ 15/month average)
                        ------
Annual savings:         $3,168  (94.6% reduction)
```

---

*This analysis is based on GCP pricing for asia-south1 (Mumbai) as of March 2026.
Cloud Run, Pub/Sub, and Identity Platform costs assume usage within free tier limits.
Cloud SQL pricing is for db-f1-micro with 10 Gi SSD storage, zonal availability.*
