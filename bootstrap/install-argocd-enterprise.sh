#!/usr/bin/env bash

# =========================================================
# ENTERPRISE ARGOCD INSTALLER
# =========================================================

set -Eeuo pipefail

# =========================================================
# COLORS
# =========================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

retry() {
    local retries=5
    local count=0

    until "$@"; do
        exit_code=$?
        count=$((count + 1))

        if [ "$count" -lt "$retries" ]; then
            warn "Retry $count/$retries..."
            sleep 10
        else
            echo "Command failed."
            return "$exit_code"
        fi
    done
}

clear

log "Installing Enterprise ArgoCD"

# =========================================================
# DOWNLOAD MANIFEST
# =========================================================

log "Downloading ArgoCD manifest..."

curl -L \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  -o /tmp/argocd-install.yaml

success "Manifest downloaded"

# =========================================================
# INSTALL CRDs FIRST
# =========================================================

log "Installing CRDs separately..."

kubectl create -f /tmp/argocd-install.yaml \
  --selector='!app.kubernetes.io/part-of=argocd' \
  || true

success "CRDs installed"

# =========================================================
# INSTALL MAIN COMPONENTS
# =========================================================

log "Installing ArgoCD components..."

retry kubectl apply \
  -n argocd \
  -f /tmp/argocd-install.yaml \
  --server-side \
  --force-conflicts

success "ArgoCD components installed"

# =========================================================
# WAIT FOR ARGOCD
# =========================================================

log "Waiting for ArgoCD server..."

kubectl wait \
  --for=condition=available \
  deployment/argocd-server \
  -n argocd \
  --timeout=600s

success "ArgoCD ready"

# =========================================================
# EXPOSE SERVICE
# =========================================================

log "Exposing ArgoCD..."

kubectl patch svc argocd-server \
  -n argocd \
  -p '{"spec":{"type":"LoadBalancer"}}'

success "ArgoCD exposed"

# =========================================================
# GET PASSWORD
# =========================================================

ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "================================================="
echo "ARGOCD ACCESS"
echo "================================================="
echo ""
echo "URL:"
echo "https://localhost:8080"
echo ""
echo "USERNAME:"
echo "admin"
echo ""
echo "PASSWORD:"
echo "${ARGO_PASSWORD}"
echo ""
echo "PORT FORWARD:"
echo ""
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "================================================="

success "Enterprise ArgoCD installation completed"
