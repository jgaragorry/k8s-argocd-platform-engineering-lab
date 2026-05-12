#!/usr/bin/env bash

# =========================================================
# ENTERPRISE ENVIRONMENT CLEANUP
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

# =========================================================
# CONFIRM ROOT
# =========================================================

if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo."
    exit 1
fi

clear

warn "THIS WILL DELETE:"
echo ""
echo "- ALL k3d clusters"
echo "- ALL Docker containers"
echo "- ALL Docker images"
echo "- ALL Docker volumes"
echo "- ALL Docker networks"
echo "- Old kubeconfig contexts"
echo ""
warn "THIS ACTION IS DESTRUCTIVE"
echo ""

read -rp "Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Cancelled."
    exit 1
fi

# =========================================================
# REMOVE K3D
# =========================================================

if command -v k3d >/dev/null 2>&1; then
    log "Removing k3d clusters..."

    k3d cluster delete --all || true

    success "k3d clusters removed"
fi

# =========================================================
# REMOVE CONTAINERS
# =========================================================

log "Removing Docker containers..."

docker rm -f $(docker ps -aq) 2>/dev/null || true

success "Containers removed"

# =========================================================
# REMOVE IMAGES
# =========================================================

log "Removing Docker images..."

docker rmi -f $(docker images -aq) 2>/dev/null || true

success "Images removed"

# =========================================================
# REMOVE VOLUMES
# =========================================================

log "Removing Docker volumes..."

docker volume rm $(docker volume ls -q) 2>/dev/null || true

success "Volumes removed"

# =========================================================
# REMOVE NETWORKS
# =========================================================

log "Removing unused Docker networks..."

docker network prune -f || true

success "Networks cleaned"

# =========================================================
# FULL DOCKER PRUNE
# =========================================================

log "Running Docker system prune..."

docker system prune -af --volumes || true

success "Docker fully cleaned"

# =========================================================
# CLEAN KUBECONFIG
# =========================================================

log "Cleaning kubeconfig..."

rm -rf ~/.kube/config || true

mkdir -p ~/.kube

success "kubeconfig cleaned"

# =========================================================
# RESTART K3S
# =========================================================

log "Restarting K3s..."

systemctl restart k3s

sleep 20

success "K3s restarted"

# =========================================================
# COPY NEW KUBECONFIG
# =========================================================

log "Configuring kubectl..."

cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

chown "$(logname):$(logname)" ~/.kube/config

chmod 600 ~/.kube/config

success "kubectl configured"

# =========================================================
# VALIDATION
# =========================================================

log "Validating cluster..."

kubectl get nodes

echo ""

success "ENVIRONMENT CLEANED SUCCESSFULLY"
