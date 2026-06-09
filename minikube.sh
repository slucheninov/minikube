#!/usr/bin/env zsh
#
# Universal Minikube cluster management script
# Supports single and multi-cluster setups with optional metrics-server installation
#
# Usage:
#   ./minikube.sh [command] [options]
#
# Commands:
#   start       - Start cluster(s)
#   stop        - Stop cluster(s)
#   delete      - Delete cluster(s)
#   status      - Show cluster status
#   metrics     - Install/uninstall metrics-server
#
# Environment variables:
#   CLUSTERS          - Comma-separated list of cluster names (default: cluster-1)
#   K8S_VERSION       - Kubernetes version (default: 1.33.6)
#   CNI               - CNI plugin: cilium, calico, or none (default: none)
#   SERVICE_CIDR      - Service cluster IP range (default: auto)
#   METRICS_SERVER    - Install metrics-server: true/false (default: false)
#   METRICS_VERSION   - Metrics-server Helm chart version (default: 3.11.0)
#   REGISTRY          - Enable in-cluster registry addon: true/false (default: false)
#   INSECURE_REGISTRIES - Comma-separated list of insecure registries to trust (default: empty)
#

set -euo pipefail

# Default configuration
readonly DEFAULT_CLUSTERS="cluster-1"
readonly DEFAULT_K8S_VERSION="1.33.10"
readonly DEFAULT_CNI=""
readonly DEFAULT_METRICS_SERVER="false"
readonly DEFAULT_METRICS_VERSION="3.11.0"
readonly METRICS_NAMESPACE="kube-system"
readonly METRICS_NAME="metrics-server"
readonly METRICS_REPO="https://kubernetes-sigs.github.io/metrics-server/"
readonly DEFAULT_REGISTRY="false"
readonly DEFAULT_INSECURE_REGISTRIES=""
readonly SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${(%):-%x}")"

# Configuration from environment or defaults
CLUSTERS="${CLUSTERS:-${DEFAULT_CLUSTERS}}"
K8S_VERSION="${K8S_VERSION:-${DEFAULT_K8S_VERSION}}"
CNI="${CNI:-${DEFAULT_CNI}}"
METRICS_SERVER="${METRICS_SERVER:-${DEFAULT_METRICS_SERVER}}"
METRICS_VERSION="${METRICS_VERSION:-${DEFAULT_METRICS_VERSION}}"
REGISTRY="${REGISTRY:-${DEFAULT_REGISTRY}}"
INSECURE_REGISTRIES="${INSECURE_REGISTRIES:-${DEFAULT_INSECURE_REGISTRIES}}"

# Service CIDR mapping for multi-cluster setups
typeset -A SERVICE_CIDR_MAP
SERVICE_CIDR_MAP[cluster-1]="172.16.1.0/24"
SERVICE_CIDR_MAP[cluster-2]="172.16.2.0/24"
SERVICE_CIDR_MAP[cluster-3]="172.16.3.0/24"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Helper functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check that minikube is installed; otherwise suggest the official install method
check_minikube_installed() {
  if command -v minikube >/dev/null 2>&1; then
    return 0
  fi

  log_error "minikube is not installed or not found in PATH."
  echo
  echo "Install minikube using the method recommended by the official documentation:"
  echo "  https://minikube.sigs.k8s.io/docs/start/"
  echo

  local os_name
  os_name="$(uname -s)"
  local arch
  arch="$(uname -m)"

  case "${os_name}" in
    Darwin)
      echo "macOS (${arch}):"
      if command -v brew >/dev/null 2>&1; then
        echo "  brew install minikube"
      else
        echo "  # Homebrew not detected; install it from https://brew.sh or use the binary below"
      fi
      if [[ "${arch}" == "arm64" ]]; then
        echo "  # Or install the binary directly:"
        echo "  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-arm64"
        echo "  sudo install minikube-darwin-arm64 /usr/local/bin/minikube && rm minikube-darwin-arm64"
      else
        echo "  # Or install the binary directly:"
        echo "  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64"
        echo "  sudo install minikube-darwin-amd64 /usr/local/bin/minikube && rm minikube-darwin-amd64"
      fi
      ;;
    Linux)
      echo "Linux (${arch}):"
      if [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]]; then
        echo "  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-arm64"
        echo "  sudo install minikube-linux-arm64 /usr/local/bin/minikube && rm minikube-linux-arm64"
      else
        echo "  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
        echo "  sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "Windows:"
      echo "  winget install Kubernetes.minikube"
      echo "  # or: choco install minikube"
      ;;
    *)
      echo "Unsupported OS: ${os_name}. See https://minikube.sigs.k8s.io/docs/start/"
      ;;
  esac

  echo
  read -q "REPLY?Attempt automatic installation now? (y/N): " || true
  echo

  if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
    install_minikube_auto "${os_name}" "${arch}" || {
      log_error "Automatic installation failed. Please install minikube manually."
      exit 1
    }
    if ! command -v minikube >/dev/null 2>&1; then
      log_error "minikube still not found in PATH after installation."
      exit 1
    fi
    log_info "minikube installed: $(minikube version --short 2>/dev/null || minikube version | head -n1)"
  else
    log_info "Please install minikube and re-run this script."
    exit 1
  fi
}

# Check that helm is installed; otherwise suggest the official install method
check_helm_installed() {
  if command -v helm >/dev/null 2>&1; then
    return 0
  fi

  log_error "helm is not installed or not found in PATH."
  echo
  echo "Install helm using the method recommended by the official documentation:"
  echo "  https://helm.sh/docs/intro/install/"
  echo

  local os_name
  os_name="$(uname -s)"
  local arch
  arch="$(uname -m)"

  case "${os_name}" in
    Darwin)
      echo "macOS (${arch}):"
      if command -v brew >/dev/null 2>&1; then
        echo "  brew install helm"
      else
        echo "  # Homebrew not detected; install it from https://brew.sh or use the installer below"
      fi
      echo "  # Or via the official installer script:"
      echo "  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
      ;;
    Linux)
      echo "Linux (${arch}):"
      echo "  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "Windows:"
      echo "  winget install Helm.Helm"
      echo "  # or: choco install kubernetes-helm"
      ;;
    *)
      echo "Unsupported OS: ${os_name}. See https://helm.sh/docs/intro/install/"
      ;;
  esac

  echo
  read -q "REPLY?Attempt automatic installation now? (y/N): " || true
  echo

  if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
    install_helm_auto "${os_name}" || {
      log_error "Automatic installation failed. Please install helm manually."
      exit 1
    }
    if ! command -v helm >/dev/null 2>&1; then
      log_error "helm still not found in PATH after installation."
      exit 1
    fi
    log_info "helm installed: $(helm version --short 2>/dev/null || helm version | head -n1)"
  else
    log_info "Please install helm and re-run this script."
    exit 1
  fi
}

# Attempt automatic helm installation based on OS
install_helm_auto() {
  local os_name="$1"

  case "${os_name}" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        log_info "Installing helm via Homebrew..."
        brew install helm
      else
        log_info "Installing helm via the official installer script..."
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      fi
      ;;
    Linux)
      log_info "Installing helm via the official installer script..."
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      ;;
    *)
      log_error "Automatic installation is not supported on ${os_name}."
      return 1
      ;;
  esac
}

# Attempt automatic installation based on OS
install_minikube_auto() {
  local os_name="$1"
  local arch="$2"

  case "${os_name}" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        log_info "Installing minikube via Homebrew..."
        brew install minikube
      else
        local bin
        if [[ "${arch}" == "arm64" ]]; then
          bin="minikube-darwin-arm64"
        else
          bin="minikube-darwin-amd64"
        fi
        log_info "Downloading ${bin}..."
        curl -LO "https://storage.googleapis.com/minikube/releases/latest/${bin}"
        sudo install "${bin}" /usr/local/bin/minikube
        rm -f "${bin}"
      fi
      ;;
    Linux)
      local bin
      if [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]]; then
        bin="minikube-linux-arm64"
      else
        bin="minikube-linux-amd64"
      fi
      log_info "Downloading ${bin}..."
      curl -LO "https://storage.googleapis.com/minikube/releases/latest/${bin}"
      sudo install "${bin}" /usr/local/bin/minikube
      rm -f "${bin}"
      ;;
    *)
      log_error "Automatic installation is not supported on ${os_name}."
      return 1
      ;;
  esac
}

# Get service CIDR for a cluster
get_service_cidr() {
  local cluster=$1
  if [[ -n "${SERVICE_CIDR:-}" ]]; then
    echo "${SERVICE_CIDR}"
  elif [[ -n "${SERVICE_CIDR_MAP[$cluster]:-}" ]]; then
    echo "${SERVICE_CIDR_MAP[$cluster]}"
  else
    echo ""
  fi
}

# Build minikube start command
build_start_command() {
  local cluster=$1
  local cmd="minikube start --kubernetes-version=${K8S_VERSION} -p ${cluster}"
  
  if [[ -n "${CNI}" ]]; then
    cmd="${cmd} --cni=${CNI}"
  fi
  
  local service_cidr=$(get_service_cidr "${cluster}")
  if [[ -n "${service_cidr}" ]]; then
    cmd="${cmd} --service-cluster-ip-range=${service_cidr}"
  fi

  if [[ -n "${INSECURE_REGISTRIES}" ]]; then
    cmd="${cmd} --insecure-registry=${INSECURE_REGISTRIES}"
  fi

  echo "${cmd}"
}

# Enable the built-in minikube registry addon for a cluster
enable_registry_addon() {
  local cluster=$1
  log_info "Enabling registry addon on ${cluster}..."
  minikube addons enable registry -p "${cluster}"
}

# Disable the built-in minikube registry addon for a cluster
disable_registry_addon() {
  local cluster=$1
  log_info "Disabling registry addon on ${cluster}..."
  minikube addons disable registry -p "${cluster}" 2>/dev/null || \
    log_warn "registry addon not enabled on ${cluster}"
}

# Start cluster(s)
start_clusters() {
  log_info "Starting Minikube cluster(s)..."
  log_info "Configuration:"
  log_info "  Clusters: ${CLUSTERS}"
  log_info "  Kubernetes version: ${K8S_VERSION}"
  log_info "  CNI: ${CNI:-default}"
  log_info "  Metrics-server: ${METRICS_SERVER}"
  log_info "  Registry addon: ${REGISTRY}"
  log_info "  Insecure registries: ${INSECURE_REGISTRIES:-none}"

  local cluster_array=("${(@s:,:)CLUSTERS}")

  for cluster in "${cluster_array[@]}"; do
    log_info "Starting cluster: ${cluster}"
    local cmd=$(build_start_command "${cluster}")
    eval "${cmd}"

    if [[ "${REGISTRY}" == "true" ]]; then
      enable_registry_addon "${cluster}"
    fi
  done

  # Install metrics-server if enabled
  if [[ "${METRICS_SERVER}" == "true" ]]; then
    log_info "Installing metrics-server..."
    install_metrics_server
  fi
  
  log_info "All clusters started successfully!"
  show_status
}

# Stop cluster(s)
stop_clusters() {
  log_info "Stopping Minikube cluster(s)..."
  
  local cluster_array=("${(@s:,:)CLUSTERS}")
  
  for cluster in "${cluster_array[@]}"; do
    log_info "Stopping cluster: ${cluster}"
    minikube stop -p "${cluster}" || log_warn "Failed to stop ${cluster}"
  done
  
  log_info "All clusters stopped!"
}

# Delete cluster(s)
delete_clusters() {
  log_warn "This will delete all cluster data!"
  read -q "REPLY?Are you sure? (y/N): "
  echo
  
  if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled."
    return
  fi
  
  log_info "Deleting Minikube cluster(s)..."
  
  local cluster_array=("${(@s:,:)CLUSTERS}")
  
  for cluster in "${cluster_array[@]}"; do
    log_info "Deleting cluster: ${cluster}"
    minikube delete -p "${cluster}" || log_warn "Failed to delete ${cluster}"
  done
  
  log_info "All clusters deleted!"
}

# Show cluster status
show_status() {
  log_info "Cluster status:"
  echo
  
  local cluster_array=("${(@s:,:)CLUSTERS}")
  
  for cluster in "${cluster_array[@]}"; do
    echo "=== ${cluster} ==="
    minikube status -p "${cluster}" 2>/dev/null || log_warn "Cluster ${cluster} is not running"
    echo
  done
}

# Initialize metrics-server Helm repository
init_metrics_server() {
  log_info "Initializing metrics-server Helm repository..."
  helm repo add metrics-server "${METRICS_REPO}" 2>/dev/null || true
  helm repo update
  log_info "Metrics-server repository initialized!"
}

# Install metrics-server
install_metrics_server() {
  log_info "Installing metrics-server..."
  
  # Initialize repo if needed
  if ! helm repo list | grep -q metrics-server; then
    init_metrics_server
  fi
  
  # Use first cluster for metrics-server installation
  local cluster_array=("${(@s:,:)CLUSTERS}")
  local primary_cluster="${cluster_array[1]}"
  
  log_info "Switching to cluster: ${primary_cluster}"
  minikube profile "${primary_cluster}"
  
  # Install with default values for Minikube compatibility
  log_info "Installing with default values (kubelet-insecure-tls for Minikube compatibility)"
  helm upgrade --install "${METRICS_NAME}" metrics-server/metrics-server \
    --version "${METRICS_VERSION}" \
    --namespace "${METRICS_NAMESPACE}" \
    --create-namespace \
    --wait \
    --set "args[0]=--kubelet-insecure-tls"
  
  log_info "Metrics-server installed successfully!"
}

# Uninstall metrics-server
uninstall_metrics_server() {
  log_info "Uninstalling metrics-server..."
  
  local cluster_array=("${(@s:,:)CLUSTERS}")
  local primary_cluster="${cluster_array[1]}"
  
  log_info "Switching to cluster: ${primary_cluster}"
  minikube profile "${primary_cluster}"
  
  helm uninstall "${METRICS_NAME}" --namespace "${METRICS_NAMESPACE}" 2>/dev/null || \
    log_warn "Metrics-server not found or already uninstalled"
  
  log_info "Metrics-server uninstalled!"
}

# Show usage information
show_usage() {
  cat << EOF
Universal Minikube Cluster Management Script

Usage:
  ${SCRIPT_NAME} [command] [options]

Commands:
  start              Start cluster(s)
  stop               Stop cluster(s)
  delete             Delete cluster(s) (with confirmation)
  status             Show cluster status
  metrics install    Install metrics-server
  metrics uninstall  Uninstall metrics-server
  registry install   Enable in-cluster registry addon
  registry uninstall Disable in-cluster registry addon
  registry port      Show host:port to reach the in-cluster registry
  help               Show this help message

Environment Variables:
  CLUSTERS            Comma-separated list of cluster names (default: cluster-1)
  K8S_VERSION         Kubernetes version (default: 1.33.6)
  CNI                 CNI plugin: cilium, calico, or empty for default (default: empty)
  SERVICE_CIDR        Service cluster IP range (default: auto-assigned)
  METRICS_SERVER      Install metrics-server on start: true/false (default: false)
  METRICS_VERSION     Metrics-server Helm chart version (default: 3.11.0)
  REGISTRY            Enable in-cluster registry addon on start: true/false (default: false)
  INSECURE_REGISTRIES Comma-separated insecure registries to trust, e.g. host:5000 (default: empty)

Examples:
  # Start single cluster
  ${SCRIPT_NAME} start

  # Start multiple clusters with Cilium CNI
  CLUSTERS="cluster-1,cluster-2" CNI=cilium ${SCRIPT_NAME} start

  # Start cluster with metrics-server
  METRICS_SERVER=true ${SCRIPT_NAME} start

  # Install metrics-server separately
  ${SCRIPT_NAME} metrics install

  # Start cluster with the in-cluster registry addon
  REGISTRY=true ${SCRIPT_NAME} start

  # Start cluster that trusts an external insecure registry
  INSECURE_REGISTRIES="192.168.49.2:5000,my-registry.lan:5000" ${SCRIPT_NAME} start

  # Enable/disable registry addon on an already running cluster
  ${SCRIPT_NAME} registry install
  ${SCRIPT_NAME} registry uninstall

  # Print the host:port for the in-cluster registry
  ${SCRIPT_NAME} registry port

  # Show cluster status
  ${SCRIPT_NAME} status

  # Stop all clusters
  ${SCRIPT_NAME} stop

  # Delete all clusters
  ${SCRIPT_NAME} delete
EOF
}

# Main command handler
main() {
  local command="${1:-}"

  # Commands that actually require minikube binary
  case "${command}" in
    start|stop|delete|status|metrics|registry)
      check_minikube_installed
      ;;
  esac

  # Commands that require helm binary (metrics-server uses Helm)
  case "${command}" in
    metrics)
      check_helm_installed
      ;;
    start)
      if [[ "${METRICS_SERVER}" == "true" ]]; then
        check_helm_installed
      fi
      ;;
  esac

  case "${command}" in
    start)
      start_clusters
      ;;
    stop)
      stop_clusters
      ;;
    delete)
      delete_clusters
      ;;
    status)
      show_status
      ;;
    metrics)
      local metrics_cmd="${2:-}"
      case "${metrics_cmd}" in
        install)
          install_metrics_server
          ;;
        uninstall)
          uninstall_metrics_server
          ;;
        *)
          log_error "Unknown metrics command: ${metrics_cmd}"
          echo "Usage: $0 metrics [install|uninstall]"
          exit 1
          ;;
      esac
      ;;
    registry)
      local registry_cmd="${2:-}"
      local cluster_array=("${(@s:,:)CLUSTERS}")
      case "${registry_cmd}" in
        install)
          for cluster in "${cluster_array[@]}"; do
            enable_registry_addon "${cluster}"
          done
          ;;
        uninstall)
          for cluster in "${cluster_array[@]}"; do
            disable_registry_addon "${cluster}"
          done
          ;;
        port)
          for cluster in "${cluster_array[@]}"; do
            local ip
            ip="$(minikube ip -p "${cluster}" 2>/dev/null || true)"
            if [[ -n "${ip}" ]]; then
              echo "${cluster}: ${ip}:5000"
            else
              log_warn "${cluster}: not running"
            fi
          done
          ;;
        *)
          log_error "Unknown registry command: ${registry_cmd}"
          echo "Usage: $0 registry [install|uninstall|port]"
          exit 1
          ;;
      esac
      ;;
    help|--help|-h)
      show_usage
      ;;
    "")
      log_error "No command specified"
      show_usage
      exit 1
      ;;
    *)
      log_error "Unknown command: ${command}"
      show_usage
      exit 1
      ;;
  esac
}

# Run main function
main "$@"
