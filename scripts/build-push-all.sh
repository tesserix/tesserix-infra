#!/usr/bin/env bash
# =============================================================================
# Build & push all Docker images to GAR
# Usage: ./build-push-all.sh [go|nextjs|all] [--dry-run] [--parallel]
#
# After images are in GAR, run:
#   cd terraform/04-services && terraform apply -var-file=../terraform.tfvars
# =============================================================================
set -euo pipefail

PROJECT="tesserix"
REGION="asia-south1"
REGISTRY="$REGION-docker.pkg.dev/$PROJECT/services"
TAG="${IMAGE_TAG:-latest}"
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"  # tesserix-new/

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
NODE_AUTH_TOKEN="${NODE_AUTH_TOKEN:-}"

DRY_RUN=false
PARALLEL=false
TARGET="${1:-all}"
FAILED=()
SUCCEEDED=()

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --parallel) PARALLEL=true ;;
  esac
done

# ---------------------------------------------------------------------------
# Colors & helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

run_cmd() {
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    return 0
  fi
  eval "$@"
}

# ---------------------------------------------------------------------------
# Service → directory mappings
# ---------------------------------------------------------------------------
# Go services: service_name → directory_name (relative to BASE_DIR)
declare -A GO_SERVICES=(
  ["audit-service"]="audit-service"
  ["tenant-service"]="tenant-service"
  ["notification-service"]="notification-service"
  ["document-service"]="document-service"
  ["location-service"]="location-service"
  ["settings-service"]="settings-service"
  ["subscription-service"]="subscription-service"
  ["verification-service"]="verification-service"
  ["tickets-service"]="tickets-service"
  ["analytics-service"]="analytics-service"
  ["feature-flags-service"]="feature-flags-service"
  ["qr-service"]="qr-service"
  ["status-service"]="status-service"
  ["tenant-router-service"]="tenant-router-service"
  ["auth-bff"]="auth-bff"
  ["mp-products"]="marketplace-products-service"
  ["mp-orders"]="marketplace-orders-service"
  ["mp-payments"]="marketplace-payment-service"
  ["mp-inventory"]="marketplace-inventory-service"
  ["mp-shipping"]="marketplace-shipping-service"
  ["mp-categories"]="marketplace-categories-service"
  ["mp-coupons"]="marketplace-coupons-service"
  ["mp-reviews"]="marketplace-reviews-service"
  ["mp-vendors"]="marketplace-vendor-service"
  ["mp-customers"]="marketplace-customers-service"
  ["mp-staff"]="marketplace-staff-service"
  ["mp-content"]="marketplace-content-service"
  ["mp-approvals"]="marketplace-approval-service"
  ["mp-gift-cards"]="marketplace-gift-cards-service"
  ["mp-marketing"]="marketplace-marketing-service"
  ["mp-connector"]="marketplace-marketplace-connector-service"
  ["mp-tax"]="marketplace-tax-service"
)

# Next.js services: service_name → directory_name
declare -A NEXTJS_SERVICES=(
  ["tesserix-home"]="tesserix-home"
  ["marketplace-onboarding"]="marketplace-onboarding"
  ["marketplace-admin"]="marketplace-admin"
  ["mp-storefront"]="marketplace-storefront"
)

# ---------------------------------------------------------------------------
# Build functions
# ---------------------------------------------------------------------------
build_go() {
  local name="$1"
  local dir="$2"
  local image="$REGISTRY/$name:$TAG"
  local src="$BASE_DIR/$dir"

  if [[ ! -d "$src" ]]; then
    warn "Directory $src not found — skipping $name"
    FAILED+=("$name (dir not found)")
    return 0
  fi

  if [[ ! -f "$src/Dockerfile" ]]; then
    warn "No Dockerfile in $src — skipping $name"
    FAILED+=("$name (no Dockerfile)")
    return 0
  fi

  log "Building $name → $image"
  if run_cmd "cd '$src' && DOCKER_BUILDKIT=1 docker build \
    --secret id=github_token,env=GITHUB_TOKEN \
    --platform linux/amd64 \
    -t '$image' ."; then
    log "Pushing $image"
    if run_cmd "docker push '$image'"; then
      ok "$name"
      SUCCEEDED+=("$name")
      return 0
    fi
  fi

  err "Failed: $name"
  FAILED+=("$name")
  return 0  # don't abort the whole run
}

build_nextjs() {
  local name="$1"
  local dir="$2"
  local image="$REGISTRY/$name:$TAG"
  local src="$BASE_DIR/$dir"

  if [[ ! -d "$src" ]]; then
    warn "Directory $src not found — skipping $name"
    FAILED+=("$name (dir not found)")
    return 0
  fi

  if [[ ! -f "$src/Dockerfile" ]]; then
    warn "No Dockerfile in $src — skipping $name"
    FAILED+=("$name (no Dockerfile)")
    return 0
  fi

  local secret_flag=""
  if [[ -n "$NODE_AUTH_TOKEN" ]]; then
    secret_flag="--secret id=NODE_AUTH_TOKEN,env=NODE_AUTH_TOKEN"
  fi

  log "Building $name → $image"
  if run_cmd "cd '$src' && docker build \
    $secret_flag \
    --platform linux/amd64 \
    -t '$image' ."; then
    log "Pushing $image"
    if run_cmd "docker push '$image'"; then
      ok "$name"
      SUCCEEDED+=("$name")
      return 0
    fi
  fi

  err "Failed: $name"
  FAILED+=("$name")
  return 0
}

build_go_parallel() {
  local name="$1"
  local dir="$2"
  local image="$REGISTRY/$name:$TAG"
  local src="$BASE_DIR/$dir"
  local logfile="/tmp/build-$name.log"

  if [[ ! -d "$src" ]] || [[ ! -f "$src/Dockerfile" ]]; then
    echo "SKIP" > "$logfile"
    return 0
  fi

  (
    cd "$src"
    DOCKER_BUILDKIT=1 docker build \
      --secret id=github_token,env=GITHUB_TOKEN \
      --platform linux/amd64 \
      -t "$image" . &>> "$logfile" && \
    docker push "$image" &>> "$logfile" && \
    echo "OK" >> "$logfile" || echo "FAIL" >> "$logfile"
  ) &
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
preflight() {
  echo "=== Build & Push All Images to GAR ==="
  echo "    Registry: $REGISTRY"
  echo "    Tag:      $TAG"
  echo "    Target:   $TARGET"
  echo "    Base dir: $BASE_DIR"
  echo ""

  if ! command -v docker &>/dev/null; then
    err "docker not found"; exit 1
  fi

  # Ensure docker auth
  gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet 2>/dev/null || true

  if [[ -z "$GITHUB_TOKEN" ]] && [[ "$TARGET" != "nextjs" ]]; then
    err "GITHUB_TOKEN not set — Go builds need it for private modules"
    echo "  export GITHUB_TOKEN=ghp_..."
    exit 1
  fi

  if $DRY_RUN; then warn "DRY RUN — no builds will execute"; fi
  if $PARALLEL; then warn "PARALLEL mode — builds run concurrently"; fi
  echo ""
}

# ---------------------------------------------------------------------------
# Main build orchestration
# ---------------------------------------------------------------------------
build_all_go() {
  echo "--- Go Services (${#GO_SERVICES[@]}) ---"
  if $PARALLEL && ! $DRY_RUN; then
    local pids=()
    for name in $(echo "${!GO_SERVICES[@]}" | tr ' ' '\n' | sort); do
      build_go_parallel "$name" "${GO_SERVICES[$name]}"
      pids+=($!)
    done

    # Wait for all builds
    local failed_count=0
    for pid in "${pids[@]}"; do
      wait "$pid" || ((failed_count++))
    done

    # Check results
    for name in $(echo "${!GO_SERVICES[@]}" | tr ' ' '\n' | sort); do
      local logfile="/tmp/build-$name.log"
      if [[ -f "$logfile" ]]; then
        if grep -q "^OK$" "$logfile" 2>/dev/null; then
          ok "$name"
          SUCCEEDED+=("$name")
        elif grep -q "^SKIP$" "$logfile" 2>/dev/null; then
          warn "$name (skipped)"
        else
          err "$name (check /tmp/build-$name.log)"
          FAILED+=("$name")
        fi
      fi
    done
  else
    for name in $(echo "${!GO_SERVICES[@]}" | tr ' ' '\n' | sort); do
      build_go "$name" "${GO_SERVICES[$name]}"
    done
  fi
}

build_all_nextjs() {
  echo ""
  echo "--- Next.js Services (${#NEXTJS_SERVICES[@]}) ---"
  for name in $(echo "${!NEXTJS_SERVICES[@]}" | tr ' ' '\n' | sort); do
    build_nextjs "$name" "${NEXTJS_SERVICES[$name]}"
  done
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
preflight

case "$TARGET" in
  go)     build_all_go ;;
  nextjs) build_all_nextjs ;;
  all)    build_all_go; build_all_nextjs ;;
  *)      err "Unknown target: $TARGET (use: go, nextjs, all)"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Succeeded: ${#SUCCEEDED[@]}${NC}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo -e "${RED}  Failed:    ${#FAILED[@]}${NC}"
  for f in "${FAILED[@]}"; do echo -e "    ${RED}✗${NC} $f"; done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  cd tesserix-infra/terraform/04-services"
echo "  terraform plan -var-file=../terraform.tfvars"
echo "  terraform apply -var-file=../terraform.tfvars"
