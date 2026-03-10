#!/usr/bin/env bash
# =============================================================================
# Tesserix Manual Deploy — All Marketplace Services
# Usage: ./deploy-all.sh [wave1|wave2|wave3|wave4|wave5|all] [--dry-run] [--skip-build]
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROJECT="tesserix"
REGION="asia-south1"
REGISTRY="asia-south1-docker.pkg.dev/tesserix/services"
TAG="${IMAGE_TAG:-manual-$(date +%Y%m%d-%H%M%S)}"
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"  # tesserix-new/
SQL_INSTANCE="tesserix:asia-south1:tesserix-main"

# Secrets — set these before running
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
NODE_AUTH_TOKEN="${NODE_AUTH_TOKEN:-}"

# Flags
DRY_RUN=false
SKIP_BUILD=false
TARGET_WAVE="${1:-all}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --skip-build) SKIP_BUILD=true ;;
  esac
done

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()   { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

run_cmd() {
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@"
  fi
}

check_health() {
  local service="$1"
  local path="${2:-/health}"
  local url
  url=$(gcloud run services describe "$service" --region "$REGION" --format='value(status.url)' 2>/dev/null || echo "")
  if [[ -z "$url" ]]; then
    warn "Could not get URL for $service — skipping health check"
    return 0
  fi
  log "Health check: $url$path"
  local attempt
  for attempt in 1 2 3 4 5; do
    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url$path" 2>/dev/null || echo "000")
    if [[ "$status" == "200" ]]; then
      ok "$service healthy (attempt $attempt)"
      return 0
    fi
    log "  attempt $attempt: HTTP $status — waiting 10s..."
    sleep 10
  done
  warn "$service health check failed after 5 attempts (may need cold start time)"
  return 0  # don't abort the whole deploy
}

# ---------------------------------------------------------------------------
# Build & Deploy functions
# ---------------------------------------------------------------------------

build_go() {
  local name="$1"
  local dir="$2"
  local image="$REGISTRY/$name:$TAG"

  if $SKIP_BUILD; then
    log "Skipping build for $name (--skip-build)"
    return
  fi

  log "Building $name from $dir ..."
  if [[ -z "$GITHUB_TOKEN" ]]; then
    err "GITHUB_TOKEN not set — Go private modules will fail"
    return 1
  fi

  run_cmd "cd '$BASE_DIR/$dir' && DOCKER_BUILDKIT=1 docker build \
    --no-cache \
    --secret id=github_token,env=GITHUB_TOKEN \
    --platform linux/amd64 \
    -t '$image' ."

  log "Pushing $image ..."
  run_cmd "docker push '$image'"
  ok "Built & pushed $name"
}

build_nextjs() {
  local name="$1"
  local dir="$2"
  shift 2
  local image="$REGISTRY/$name:$TAG"

  if $SKIP_BUILD; then
    log "Skipping build for $name (--skip-build)"
    return
  fi

  log "Building $name from $dir ..."
  local extra_args=""
  for arg in "$@"; do
    extra_args+=" --build-arg $arg"
  done

  # Some Next.js apps need NODE_AUTH_TOKEN for private packages
  local secret_flag=""
  if [[ -n "$NODE_AUTH_TOKEN" ]]; then
    secret_flag="--secret id=NODE_AUTH_TOKEN,env=NODE_AUTH_TOKEN"
  fi

  run_cmd "cd '$BASE_DIR/$dir' && docker build \
    $secret_flag \
    --platform linux/amd64 \
    $extra_args \
    -t '$image' ."

  log "Pushing $image ..."
  run_cmd "docker push '$image'"
  ok "Built & pushed $name"
}

deploy_simple() {
  local name="$1"
  local image="$REGISTRY/$name:$TAG"

  log "Deploying $name (no sidecar) ..."
  run_cmd "gcloud run deploy '$name' \
    --image '$image' \
    --region '$REGION' \
    --project '$PROJECT' \
    --quiet"
  ok "Deployed $name"
}

deploy_with_sidecar() {
  local name="$1"
  local image="$REGISTRY/$name:$TAG"

  log "Deploying $name (with sidecar) ..."
  run_cmd "gcloud beta run services update '$name' \
    --container '$name' \
    --image '$image' \
    --region '$REGION' \
    --project '$PROJECT' \
    --quiet"
  ok "Deployed $name"
}

deploy_nextjs_simple() {
  local name="$1"
  local image="$REGISTRY/$name:$TAG"

  log "Deploying $name (Next.js, no sidecar) ..."
  run_cmd "gcloud run deploy '$name' \
    --image '$image' \
    --region '$REGION' \
    --project '$PROJECT' \
    --quiet"
  ok "Deployed $name"
}

deploy_nextjs_sidecar() {
  local name="$1"
  local image="$REGISTRY/$name:$TAG"

  log "Deploying $name (Next.js, with sidecar) ..."
  run_cmd "gcloud beta run services update '$name' \
    --container '$name' \
    --image '$image' \
    --region '$REGION' \
    --project '$PROJECT' \
    --quiet"
  ok "Deployed $name"
}

# ---------------------------------------------------------------------------
# WAVE 1 — Foundation (no service dependencies)
# ---------------------------------------------------------------------------
wave1() {
  header "WAVE 1 — Foundation Services"

  # feature-flags-service (no DB, no sidecar)
  build_go "feature-flags-service" "feature-flags-service"
  deploy_simple "feature-flags-service"
  check_health "feature-flags-service"

  # status-service (no DB, no sidecar)
  build_go "status-service" "status-service"
  deploy_simple "status-service"
  check_health "status-service"

  # qr-service (no DB, no sidecar)
  build_go "qr-service" "qr-service"
  deploy_simple "qr-service"
  check_health "qr-service"

  # settings-service (DB, sidecar)
  build_go "settings-service" "settings-service"
  deploy_with_sidecar "settings-service"
  check_health "settings-service"

  # analytics-service (DB, sidecar)
  build_go "analytics-service" "analytics-service"
  deploy_with_sidecar "analytics-service"
  check_health "analytics-service"

  ok "Wave 1 complete"
}

# ---------------------------------------------------------------------------
# WAVE 2 — Core Platform (depended on by marketplace)
# ---------------------------------------------------------------------------
wave2() {
  header "WAVE 2 — Core Platform Services"

  # --- No inter-dependencies within this sub-group ---
  build_go "tenant-service" "tenant-service"
  deploy_with_sidecar "tenant-service"
  check_health "tenant-service"

  build_go "notification-service" "notification-service"
  deploy_with_sidecar "notification-service"
  check_health "notification-service"

  build_go "document-service" "document-service"
  deploy_with_sidecar "document-service"
  check_health "document-service"

  build_go "location-service" "location-service"
  deploy_with_sidecar "location-service"
  check_health "location-service"

  build_go "subscription-service" "subscription-service"
  deploy_with_sidecar "subscription-service"
  check_health "subscription-service"

  build_go "audit-service" "audit-service"
  deploy_with_sidecar "audit-service"
  check_health "audit-service"

  # --- Depends on notification-service ---
  build_go "verification-service" "verification-service"
  deploy_with_sidecar "verification-service"
  check_health "verification-service"

  # --- Depends on tenant, notification, document ---
  build_go "tickets-service" "tickets-service"
  deploy_with_sidecar "tickets-service"
  check_health "tickets-service"

  # --- Depends on notification, audit ---
  build_go "tenant-router-service" "tenant-router-service"
  deploy_with_sidecar "tenant-router-service"
  check_health "tenant-router-service"

  # --- Depends on openfga, tenant-service ---
  build_go "auth-bff" "auth-bff"
  deploy_simple "auth-bff"
  check_health "auth-bff"

  ok "Wave 2 complete"
}

# ---------------------------------------------------------------------------
# WAVE 3 — Marketplace Backend Services
# ---------------------------------------------------------------------------
wave3() {
  header "WAVE 3 — Marketplace Backend Services"

  # --- Tier 1: No marketplace inter-dependencies ---
  build_go "mp-inventory" "marketplace-inventory-service"
  deploy_with_sidecar "mp-inventory"
  check_health "mp-inventory"

  build_go "mp-shipping" "marketplace-shipping-service"
  deploy_with_sidecar "mp-shipping"
  check_health "mp-shipping"

  build_go "mp-coupons" "marketplace-coupons-service"
  deploy_with_sidecar "mp-coupons"
  check_health "mp-coupons"

  build_go "mp-tax" "marketplace-tax-service"
  deploy_with_sidecar "mp-tax"
  check_health "mp-tax"

  build_go "mp-customers" "marketplace-customers-service"
  deploy_with_sidecar "mp-customers"
  check_health "mp-customers"

  build_go "mp-vendors" "marketplace-vendor-service"
  deploy_with_sidecar "mp-vendors"
  check_health "mp-vendors"

  build_go "mp-staff" "marketplace-staff-service"
  deploy_with_sidecar "mp-staff"
  check_health "mp-staff"

  build_go "mp-reviews" "marketplace-reviews-service"
  deploy_with_sidecar "mp-reviews"
  check_health "mp-reviews"

  # --- Tier 2: Depends on mp-staff ---
  build_go "mp-approvals" "marketplace-approval-service"
  deploy_with_sidecar "mp-approvals"
  check_health "mp-approvals"

  build_go "mp-content" "marketplace-content-service"
  deploy_with_sidecar "mp-content"
  check_health "mp-content"

  build_go "mp-gift-cards" "marketplace-gift-cards-service"
  deploy_with_sidecar "mp-gift-cards"
  check_health "mp-gift-cards"

  build_go "mp-marketing" "marketplace-marketing-service"
  deploy_with_sidecar "mp-marketing"
  check_health "mp-marketing"

  # --- Tier 3: Depends on mp-approvals ---
  build_go "mp-categories" "marketplace-categories-service"
  deploy_with_sidecar "mp-categories"
  check_health "mp-categories"

  build_go "mp-products" "marketplace-products-service"
  deploy_with_sidecar "mp-products"
  check_health "mp-products"

  build_go "mp-payments" "marketplace-payment-service"
  deploy_with_sidecar "mp-payments"
  check_health "mp-payments"

  # --- Tier 4: Depends on mp-inventory, mp-payments, mp-products ---
  build_go "mp-orders" "marketplace-orders-service"
  deploy_with_sidecar "mp-orders"
  check_health "mp-orders"

  # --- Tier 5: Depends on mp-products, mp-orders, mp-inventory ---
  build_go "mp-connector" "marketplace-marketplace-connector-service"
  deploy_with_sidecar "mp-connector"
  check_health "mp-connector"

  ok "Wave 3 complete"
}

# ---------------------------------------------------------------------------
# WAVE 4 — Frontend Apps (user journey order)
# ---------------------------------------------------------------------------
wave4() {
  header "WAVE 4 — Frontend Apps"

  # tesserix-home (platform admin — no sidecar)
  build_nextjs "tesserix-home" "tesserix-home"
  deploy_nextjs_simple "tesserix-home"
  check_health "tesserix-home" "/api/health"

  # marketplace-onboarding (has sidecar for DB)
  build_nextjs "marketplace-onboarding" "marketplace-onboarding" \
    "NEXT_PUBLIC_BASE_DOMAIN=mark8ly.com" \
    "NEXT_PUBLIC_SITE_URL=https://mark8ly.com" \
    "NEXT_PUBLIC_ECOMMERCE_ADMIN_URL=https://admin.mark8ly.com"
  deploy_nextjs_sidecar "marketplace-onboarding"
  check_health "marketplace-onboarding" "/api/health"

  # marketplace-admin (no sidecar)
  build_nextjs "marketplace-admin" "marketplace-admin"
  deploy_nextjs_simple "marketplace-admin"
  check_health "marketplace-admin" "/api/health"

  # mp-storefront (no sidecar)
  build_nextjs "mp-storefront" "marketplace-storefront"
  deploy_nextjs_simple "mp-storefront"
  check_health "mp-storefront" "/api/health"

  ok "Wave 4 complete"
}

# ---------------------------------------------------------------------------
# WAVE 5 — Edge Router (Cloudflare Worker)
# ---------------------------------------------------------------------------
wave5() {
  header "WAVE 5 — Cloudflare Worker"

  log "Deploying Cloudflare Worker ..."
  run_cmd "cd '$BASE_DIR/tesserix-infra/cloudflare' && npx wrangler deploy"

  ok "Wave 5 complete"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
  header "Preflight Checks"

  # Check gcloud
  if ! command -v gcloud &>/dev/null; then
    err "gcloud CLI not found — install Google Cloud SDK"
    exit 1
  fi
  ok "gcloud CLI found"

  # Check docker
  if ! command -v docker &>/dev/null; then
    err "docker not found"
    exit 1
  fi
  ok "docker found"

  # Check project
  local current_project
  current_project=$(gcloud config get-value project 2>/dev/null)
  if [[ "$current_project" != "$PROJECT" ]]; then
    warn "Current gcloud project is '$current_project', expected '$PROJECT'"
    log "Setting project to $PROJECT ..."
    run_cmd "gcloud config set project $PROJECT"
  fi
  ok "GCP project: $PROJECT"

  # Check docker auth
  log "Ensuring docker is authenticated to GAR ..."
  run_cmd "gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet 2>/dev/null || true"
  ok "Docker auth configured"

  # Check secrets
  if [[ -z "$GITHUB_TOKEN" ]]; then
    warn "GITHUB_TOKEN not set — Go builds will fail for private modules"
    warn "Set it: export GITHUB_TOKEN=ghp_..."
  else
    ok "GITHUB_TOKEN set"
  fi

  if [[ -z "$NODE_AUTH_TOKEN" ]]; then
    warn "NODE_AUTH_TOKEN not set — Next.js builds with private packages may fail"
    warn "Set it: export NODE_AUTH_TOKEN=ghp_..."
  else
    ok "NODE_AUTH_TOKEN set"
  fi

  echo ""
  log "Image tag: $TAG"
  log "Registry: $REGISTRY"
  log "Target: $TARGET_WAVE"
  if $DRY_RUN; then warn "DRY RUN — no actual commands will execute"; fi
  if $SKIP_BUILD; then warn "SKIP BUILD — will only deploy (using latest images in GAR)"; fi
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  preflight

  case "$TARGET_WAVE" in
    wave1) wave1 ;;
    wave2) wave2 ;;
    wave3) wave3 ;;
    wave4) wave4 ;;
    wave5) wave5 ;;
    all)
      wave1
      wave2
      wave3
      wave4
      wave5
      ;;
    *)
      err "Unknown wave: $TARGET_WAVE"
      echo "Usage: $0 [wave1|wave2|wave3|wave4|wave5|all] [--dry-run] [--skip-build]"
      exit 1
      ;;
  esac

  header "DEPLOYMENT COMPLETE"
  echo ""
  echo "  Tag used: $TAG"
  echo ""
  echo "  Verify user journeys:"
  echo "    Onboarding:  https://mark8ly.com"
  echo "    Admin:       https://{slug}-admin.mark8ly.com"
  echo "    Storefront:  https://{slug}.mark8ly.com"
  echo "    Platform:    https://tesserix.app"
  echo ""
}

main
