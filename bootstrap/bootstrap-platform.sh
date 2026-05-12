#!/usr/bin/env bash

# =========================================================
# ENTERPRISE GITOPS PLATFORM BOOTSTRAP
# =========================================================

set -Eeuo pipefail

# =========================================================
# COLORS
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =========================================================
# FUNCTIONS
# =========================================================

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

namespace_exists() {
    kubectl get namespace "$1" >/dev/null 2>&1
}

# =========================================================
# START
# =========================================================

clear

log "Enterprise GitOps Platform Bootstrap"

# =========================================================
# VALIDATE CLUSTER
# =========================================================

log "Validating Kubernetes cluster..."

kubectl get nodes

# =========================================================
# CREATE NAMESPACES
# =========================================================

NAMESPACES=(
    ingress-nginx
    argocd
    monitoring
    platform
    applications
)

log "Creating namespaces..."

for ns in "${NAMESPACES[@]}"; do

    if namespace_exists "$ns"; then
        success "Namespace $ns already exists"
    else
        kubectl create namespace "$ns"
        success "Namespace $ns created"
    fi

done

# =========================================================
# INSTALL INGRESS NGINX
# =========================================================

log "Installing ingress-nginx..."

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true

helm repo update

if helm status ingress-nginx -n ingress-nginx >/dev/null 2>&1; then
    success "Ingress already installed"
else

    retry helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --set controller.replicaCount=1 \
      --set controller.service.type=LoadBalancer \
      --set controller.resources.requests.cpu=100m \
      --set controller.resources.requests.memory=128Mi \
      --set controller.resources.limits.cpu=200m \
      --set controller.resources.limits.memory=256Mi

    success "Ingress installed"

fi

# =========================================================
# WAIT FOR INGRESS
# =========================================================

log "Waiting for ingress controller..."

kubectl wait \
  --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

success "Ingress controller ready"

# =========================================================
# INSTALL ARGOCD
# =========================================================

log "Installing ArgoCD..."

if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    success "ArgoCD already installed"
else

    retry kubectl apply -n argocd \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    success "ArgoCD installed"

fi

# =========================================================
# WAIT FOR ARGOCD
# =========================================================

log "Waiting for ArgoCD..."

kubectl wait \
  --for=condition=available \
  deployment/argocd-server \
  -n argocd \
  --timeout=600s

success "ArgoCD ready"

# =========================================================
# PATCH ARGOCD SERVER
# =========================================================

log "Exposing ArgoCD via LoadBalancer..."

kubectl patch svc argocd-server \
  -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

success "ArgoCD exposed"

# =========================================================
# GET ARGOCD PASSWORD
# =========================================================

log "Getting ArgoCD admin password..."

ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "================================================="
echo "ARGOCD ACCESS"
echo "================================================="
echo ""
echo "USERNAME: admin"
echo "PASSWORD: ${ARGO_PASSWORD}"
echo ""
echo "PORT FORWARD COMMAND:"
echo ""
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "OPEN:"
echo ""
echo "https://localhost:8080"
echo ""
echo "================================================="

# =========================================================
# PLATFORM SUMMARY
# =========================================================

echo ""
echo "================================================="
echo "PLATFORM COMPONENTS"
echo "================================================="
echo ""

kubectl get ns

echo ""
echo "================================================="

success "Enterprise platform bootstrap completed"
