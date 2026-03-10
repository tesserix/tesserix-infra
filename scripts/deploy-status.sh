#!/usr/bin/env bash
# =============================================================================
# Tesserix Deploy Status — Check all Cloud Run services
# Usage: ./deploy-status.sh [--health] [--wave1|--wave2|--wave3|--wave4|--all]
# =============================================================================
set -euo pipefail

PROJECT="tesserix"
REGION="asia-south1"
CHECK_HEALTH=false
TARGET="all"

for arg in "$@"; do
  case "$arg" in
    --health) CHECK_HEALTH=true ;;
    --wave1)  TARGET="wave1" ;;
    --wave2)  TARGET="wave2" ;;
    --wave3)  TARGET="wave3" ;;
    --wave4)  TARGET="wave4" ;;
    --all)    TARGET="all" ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

header() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# Service definitions: "cloud-run-name|health-path|has-sidecar"
WAVE1=(
  "feature-flags-service|/health|no"
  "status-service|/health|no"
  "qr-service|/health|no"
  "settings-service|/health|yes"
  "analytics-service|/health|yes"
)

WAVE2=(
  "tenant-service|/health|yes"
  "notification-service|/health|yes"
  "document-service|/health|yes"
  "location-service|/health|yes"
  "subscription-service|/health|yes"
  "audit-service|/health|yes"
  "verification-service|/health|yes"
  "tickets-service|/health|yes"
  "tenant-router-service|/health|yes"
  "auth-bff|/health|no"
)

WAVE3=(
  "mp-inventory|/health|yes"
  "mp-shipping|/health|yes"
  "mp-coupons|/health|yes"
  "mp-tax|/health|yes"
  "mp-customers|/health|yes"
  "mp-vendors|/health|yes"
  "mp-staff|/health|yes"
  "mp-reviews|/health|yes"
  "mp-approvals|/health|yes"
  "mp-content|/health|yes"
  "mp-gift-cards|/health|yes"
  "mp-marketing|/health|yes"
  "mp-categories|/health|yes"
  "mp-products|/health|yes"
  "mp-payments|/health|yes"
  "mp-orders|/health|yes"
  "mp-connector|/health|yes"
)

WAVE4=(
  "tesserix-home|/api/health|no"
  "marketplace-onboarding|/api/health|yes"
  "marketplace-admin|/api/health|no"
  "mp-storefront|/api/health|no"
)

# Collect services based on target
declare -a SERVICES
case "$TARGET" in
  wave1) SERVICES=("${WAVE1[@]}") ;;
  wave2) SERVICES=("${WAVE2[@]}") ;;
  wave3) SERVICES=("${WAVE3[@]}") ;;
  wave4) SERVICES=("${WAVE4[@]}") ;;
  all)   SERVICES=("${WAVE1[@]}" "${WAVE2[@]}" "${WAVE3[@]}" "${WAVE4[@]}") ;;
esac

# Table header
printf "\n"
printf "${DIM}%-28s %-12s %-22s %-44s${NC}\n" "SERVICE" "STATUS" "IMAGE TAG" "LAST DEPLOYED"
printf "${DIM}%-28s %-12s %-22s %-44s${NC}\n" "───────────────────────────" "───────────" "─────────────────────" "───────────────────────────────────────────"

total=0
active=0
failed=0
placeholder=0
not_found=0

current_wave=""
check_wave() {
  local svc="$1"
  local wave_label=""
  for w in "${WAVE1[@]}"; do [[ "${w%%|*}" == "$svc" ]] && wave_label="WAVE 1 — Foundation"; done
  for w in "${WAVE2[@]}"; do [[ "${w%%|*}" == "$svc" ]] && wave_label="WAVE 2 — Core Platform"; done
  for w in "${WAVE3[@]}"; do [[ "${w%%|*}" == "$svc" ]] && wave_label="WAVE 3 — Marketplace Backend"; done
  for w in "${WAVE4[@]}"; do [[ "${w%%|*}" == "$svc" ]] && wave_label="WAVE 4 — Frontends"; done
  if [[ "$wave_label" != "$current_wave" ]]; then
    current_wave="$wave_label"
    [[ "$TARGET" == "all" ]] && header "$wave_label"
  fi
}

for entry in "${SERVICES[@]}"; do
  IFS='|' read -r name health_path has_sidecar <<< "$entry"
  total=$((total + 1))

  [[ "$TARGET" == "all" ]] && check_wave "$name"

  # Get service info
  info=$(gcloud run services describe "$name" \
    --region "$REGION" \
    --project "$PROJECT" \
    --format='value(status.conditions[0].status,status.url,spec.template.spec.containers[0].image,status.conditions[0].lastTransitionTime)' \
    2>/dev/null || echo "NOT_FOUND")

  if [[ "$info" == "NOT_FOUND" ]]; then
    printf "  ${RED}%-26s${NC} %-12s %-22s %-44s\n" "$name" "NOT FOUND" "—" "—"
    not_found=$((not_found + 1))
    continue
  fi

  IFS=$'\t' read -r status url image last_deploy <<< "$info"

  # Extract image tag
  tag="${image##*:}"
  if [[ "$tag" == "latest" ]] || [[ "$image" == *"cloudrun/hello"* ]]; then
    tag="placeholder"
  fi

  # Format last deploy time
  if [[ -n "$last_deploy" ]]; then
    deploy_display="$last_deploy"
  else
    deploy_display="—"
  fi

  # Determine status
  if [[ "$image" == *"cloudrun/hello"* ]]; then
    printf "  ${YELLOW}%-26s${NC} ${YELLOW}%-12s${NC} ${DIM}%-22s${NC} ${DIM}%-44s${NC}\n" \
      "$name" "PLACEHOLDER" "$tag" "$deploy_display"
    placeholder=$((placeholder + 1))
  elif [[ "$status" == "True" ]]; then
    printf "  ${GREEN}%-26s${NC} ${GREEN}%-12s${NC} %-22s ${DIM}%-44s${NC}\n" \
      "$name" "ACTIVE" "$tag" "$deploy_display"
    active=$((active + 1))

    # Health check if requested
    if $CHECK_HEALTH && [[ -n "$url" ]]; then
      http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}${health_path}" 2>/dev/null || echo "000")
      if [[ "$http_code" == "200" ]]; then
        printf "  ${DIM}  └─ health: ${GREEN}OK${NC} ${DIM}(HTTP 200)${NC}\n"
      else
        printf "  ${DIM}  └─ health: ${RED}FAIL${NC} ${DIM}(HTTP $http_code)${NC}\n"
      fi
    fi
  else
    printf "  ${RED}%-26s${NC} ${RED}%-12s${NC} %-22s ${DIM}%-44s${NC}\n" \
      "$name" "FAILED" "$tag" "$deploy_display"
    failed=$((failed + 1))
  fi
done

# Summary
echo ""
echo -e "${CYAN}━━━ Summary ━━━${NC}"
printf "  Total: %d  |  " "$total"
printf "${GREEN}Active: %d${NC}  |  " "$active"
printf "${YELLOW}Placeholder: %d${NC}  |  " "$placeholder"
printf "${RED}Failed: %d${NC}  |  " "$failed"
printf "${RED}Not Found: %d${NC}\n" "$not_found"
echo ""

if [[ $placeholder -gt 0 ]]; then
  echo -e "${YELLOW}Placeholder services need their first real deploy (currently using gcr.io/cloudrun/hello).${NC}"
fi
if [[ $failed -gt 0 ]]; then
  echo -e "${RED}Failed services need investigation — check logs with:${NC}"
  echo -e "  gcloud run services logs read <service-name> --region $REGION --limit 50"
fi
echo ""
