#!/usr/bin/env bash
# =============================================================================
# Import all existing Cloud Run services into Terraform 04-services state
# Usage: ./import-cloud-run.sh [--dry-run]
# =============================================================================
set -euo pipefail

PROJECT="tesserix"
REGION="asia-south1"
TF_DIR="$(cd "$(dirname "$0")/../terraform/04-services" && pwd)"
TFVARS="$(cd "$(dirname "$0")/../terraform" && pwd)/terraform.tfvars"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

import_svc() {
  local resource="$1"
  local service="$2"
  local import_id="projects/$PROJECT/locations/$REGION/services/$service"

  # Check if already in state
  if terraform -chdir="$TF_DIR" state show "$resource" &>/dev/null; then
    echo -e "${YELLOW}[SKIP]${NC} $resource (already in state)"
    return
  fi

  # Check if service exists in GCP
  if ! gcloud run services describe "$service" --region="$REGION" --format="value(name)" &>/dev/null; then
    echo -e "${YELLOW}[SKIP]${NC} $service (does not exist in GCP)"
    return
  fi

  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} terraform import '$resource' '$import_id'"
  else
    echo -n "Importing $service ... "
    if terraform -chdir="$TF_DIR" import -var-file="$TFVARS" "$resource" "$import_id" &>/dev/null; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}FAILED${NC}"
    fi
  fi
}

echo "=== Importing Cloud Run services into Terraform state ==="
echo "    TF dir: $TF_DIR"
echo "    Project: $PROJECT / $REGION"
echo ""

# --- Special services (individually defined) ---
echo "--- Special Services ---"
import_svc 'google_cloud_run_v2_service.openfga'                'openfga'
import_svc 'google_cloud_run_v2_service.auth_bff'               'auth-bff'
import_svc 'google_cloud_run_v2_service.tesserix_home'          'tesserix-home'
import_svc 'google_cloud_run_v2_service.marketplace_onboarding' 'marketplace-onboarding'
import_svc 'google_cloud_run_v2_service.marketplace_admin'      'marketplace-admin'
import_svc 'google_cloud_run_v2_service.mp_storefront'          'mp-storefront'
import_svc 'google_cloud_run_v2_service.status_service'         'status-service'

# --- Base tier (no service_urls dependencies) ---
echo ""
echo "--- Base Tier ---"
for svc in \
  audit-service tenant-service notification-service document-service \
  location-service settings-service analytics-service \
  mp-inventory mp-shipping mp-coupons mp-reviews mp-vendors \
  mp-staff mp-content mp-approvals mp-gift-cards mp-tax; do
  import_svc "google_cloud_run_v2_service.base[\"$svc\"]" "$svc"
done

# --- Dependent tier (references base services) ---
echo ""
echo "--- Dependent Tier ---"
for svc in \
  tickets-service subscription-service verification-service \
  mp-products mp-payments mp-categories mp-customers \
  mp-marketing mp-connector tenant-router-service; do
  import_svc "google_cloud_run_v2_service.dependent[\"$svc\"]" "$svc"
done

# --- Tier 3 (references both base and dependent) ---
echo ""
echo "--- Tier 3 ---"
import_svc 'google_cloud_run_v2_service.tier3["mp-orders"]' 'mp-orders'

# --- Simple stateless (no DB, no sidecar) ---
echo ""
echo "--- Simple Services ---"
import_svc 'google_cloud_run_v2_service.simple["qr-service"]'            'qr-service'
import_svc 'google_cloud_run_v2_service.simple["feature-flags-service"]' 'feature-flags-service'

echo ""
echo "=== Import complete ==="
echo ""
echo "Next steps:"
echo "  cd $TF_DIR"
echo "  terraform plan -var-file=../terraform.tfvars"
echo "  terraform apply -var-file=../terraform.tfvars"
