#!/usr/bin/env bash

# =========================================================
# ENTERPRISE GITOPS PLATFORM LAB
# install-prereqs.sh
# =========================================================

set -Eeuo pipefail

# =========================================================
# GLOBALS
# =========================================================

LOG_FILE="/tmp/platform-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

retry() {
    local retries=5
    local count=0

    until "$@"; do
        exit_code=$?
        count=$((count + 1))

        if [ "$count" -lt "$retries" ]; then
            warn "Retry $count/$retries..."
            sleep 5
        else
            error "Command failed after retries."
            return "$exit_code"
        fi
    done
}

require_sudo() {
    if [ "$EUID" -ne 0 ]; then
        error "Run with sudo."
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =========================================================
# LOCK FILE
# =========================================================

LOCK_FILE="/tmp/platform-bootstrap.lock"

exec 200>"$LOCK_FILE"

flock -n 200 || {
    error "Another installation is running."
    exit 1
}

# =========================================================
# START
# =========================================================

clear

log "Enterprise GitOps Platform Lab"
log "Starting prerequisites installation..."

# =========================================================
# UPDATE SYSTEM
# =========================================================

log "Updating repositories..."

retry apt-get update -y

retry apt-get upgrade -y

# =========================================================
# BASE PACKAGES
# =========================================================

PACKAGES=(
    curl
    wget
    git
    jq
    unzip
    tar
    vim
    nano
    ca-certificates
    apt-transport-https
    gnupg
    lsb-release
    software-properties-common
    net-tools
)

log "Installing base packages..."

for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        success "$pkg already installed"
    else
        retry apt-get install -y "$pkg"
        success "$pkg installed"
    fi
done

# =========================================================
# DOCKER
# =========================================================

if command_exists docker; then
    success "Docker already installed"
else
    log "Installing Docker..."

    retry curl -fsSL https://get.docker.com | sh

    usermod -aG docker "$SUDO_USER"

    systemctl enable docker
    systemctl start docker

    success "Docker installed"
fi

# =========================================================
# KUBECTL
# =========================================================

if command_exists kubectl; then
    success "kubectl already installed"
else
    log "Installing kubectl..."

    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    rm -f kubectl

    success "kubectl installed"
fi

# =========================================================
# HELM
# =========================================================

if command_exists helm; then
    success "Helm already installed"
else
    log "Installing Helm..."

    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    success "Helm installed"
fi

# =========================================================
# TERRAFORM
# =========================================================

if command_exists terraform; then
    success "Terraform already installed"
else
    log "Installing Terraform..."

    wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com \
    $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list

    retry apt-get update -y

    retry apt-get install -y terraform

    success "Terraform installed"
fi

# =========================================================
# TERRAGRUNT
# =========================================================

if command_exists terragrunt; then
    success "Terragrunt already installed"
else
    log "Installing Terragrunt..."

    TERRAGRUNT_VERSION="0.67.4"

    wget -O /usr/local/bin/terragrunt \
    "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64"

    chmod +x /usr/local/bin/terragrunt

    success "Terragrunt installed"
fi

# =========================================================
# K3S
# =========================================================

if command_exists k3s; then
    success "K3s already installed"
else
    log "Installing K3s..."

    curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable traefik" \
    sh -

    success "K3s installed"
fi

# =========================================================
# ARGOCD CLI
# =========================================================

if command_exists argocd; then
    success "ArgoCD CLI already installed"
else
    log "Installing ArgoCD CLI..."

    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | jq -r .tag_name)

    curl -sSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"

    chmod +x /usr/local/bin/argocd

    success "ArgoCD CLI installed"
fi

# =========================================================
# SOPS
# =========================================================

if command_exists sops; then
    success "SOPS already installed"
else
    log "Installing SOPS..."

    SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | jq -r .tag_name)

    ARCH="amd64"

    DEB_FILE="sops_${SOPS_VERSION#v}_${ARCH}.deb"

    DOWNLOAD_URL="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/${DEB_FILE}"

    log "Downloading SOPS from:"
    echo "$DOWNLOAD_URL"

    retry wget -O "/tmp/${DEB_FILE}" "$DOWNLOAD_URL"

    dpkg -i "/tmp/${DEB_FILE}"

    rm -f "/tmp/${DEB_FILE}"

    success "SOPS installed"
fi

# =========================================================
# AGE
# =========================================================

if command_exists age; then
    success "age already installed"
else
    log "Installing age..."

    apt-get install -y age

    success "age installed"
fi

# =========================================================
# TRIVY
# =========================================================

if command_exists trivy; then
    success "Trivy already installed"
else
    log "Installing Trivy..."

    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
    gpg --dearmor | \
    tee /usr/share/keyrings/trivy.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
    https://aquasecurity.github.io/trivy-repo/deb generic main" | \
    tee /etc/apt/sources.list.d/trivy.list

    retry apt-get update -y

    retry apt-get install -y trivy

    success "Trivy installed"
fi

# =========================================================
# FINAL VALIDATION
# =========================================================

log "Validating installations..."

TOOLS=(
    docker
    kubectl
    helm
    terraform
    terragrunt
    argocd
    sops
    age
    trivy
)

for tool in "${TOOLS[@]}"; do
    if command_exists "$tool"; then
        success "$tool OK"
    else
        error "$tool missing"
        exit 1
    fi
done

# =========================================================
# FINAL MESSAGE
# =========================================================

success "ALL PREREQUISITES INSTALLED SUCCESSFULLY"

echo ""
echo "IMPORTANT:"
echo "Close WSL completely and reopen it."
echo ""

success "Installation completed."
