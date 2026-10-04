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
#   updates     - Check stable Minikube and Kubernetes releases
#   metrics     - Install/uninstall metrics-server
#   registry    - Enable/disable in-cluster registry addon, show its host:port
#
# Environment variables:
#   CLUSTERS          - Comma-separated list of cluster names (default: cluster-1)
#   K8S_VERSION       - Kubernetes version (default: 1.35.9)
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
readonly DEFAULT_K8S_VERSION="1.35.9"
readonly DEFAULT_CNI=""
readonly DEFAULT_METRICS_SERVER="false"
readonly DEFAULT_METRICS_VERSION="3.11.0"
readonly METRICS_NAMESPACE="kube-system"
readonly METRICS_NAME="metrics-server"
readonly METRICS_REPO="https://kubernetes-sigs.github.io/metrics-server/"
readonly DEFAULT_REGISTRY="false"
readonly DEFAULT_INSECURE_REGISTRIES=""
readonly SCRIPT_NAME="$(basename "${(%):-%x}")"

# Configuration from environment or defaults
CLUSTERS="${CLUSTERS:-${DEFAULT_CLUSTERS}}"
K8S_VERSION="${K8S_VERSION:-${DEFAULT_K8S_VERSION}}"
CNI="${CNI:-${DEFAULT_CNI}}"
METRICS_SERVER="${METRICS_SERVER:-${DEFAULT_METRICS_SERVER}}"
METRICS_VERSION="${METRICS_VERSION:-${DEFAULT_METRICS_VERSION}}"
REGISTRY="${REGISTRY:-${DEFAULT_REGISTRY}}"
INSECURE_REGISTRIES="${INSECURE_REGISTRIES:-${DEFAULT_INSECURE_REGISTRIES}}"
typeset -ra CLUSTER_LIST=("${(@s:,:)CLUSTERS}")

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

# Keep installation separate from cluster operations. Only a local package
# manager is automated; never execute an unpinned downloaded installer.
ensure_installed() {
  local tool="$1" docs_url="$2"
  command -v "${tool}" >/dev/null 2>&1 && return 0
  log_error "${tool} is not installed. Installation guide: ${docs_url}"
  if [[ -t 0 ]] && command -v brew >/dev/null 2>&1; then
    local REPLY=""
    read -q "REPLY?Install ${tool} with Homebrew? (y/N): " || true
    echo
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
      brew install "${tool}" || return 1
      command -v "${tool}" >/dev/null 2>&1 && return 0
    fi
  fi
  return 1
}

# Validate before invoking tools or using profile names as file paths.
validate_configuration() {
  local cluster flag
  local -A seen
  for cluster in "${CLUSTER_LIST[@]}"; do
    if [[ ! "${cluster}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
      log_error "Invalid cluster name: ${cluster}. Use letters, digits, underscores and hyphens, starting with a letter or digit."
      return 1
    fi
    if [[ -n "${seen[$cluster]:-}" ]]; then
      log_error "Duplicate cluster name: ${cluster}"
      return 1
    fi
    seen[$cluster]=1
  done
  for flag in METRICS_SERVER REGISTRY; do
    if [[ "${(P)flag}" != true && "${(P)flag}" != false ]]; then
      log_error "${flag} must be true or false."
      return 1
    fi
  done
}

# Try every profile, but report partial failures to callers and CI.
run_cluster_command() {
  local action="$1" cluster
  local failed=0
  for cluster in "${CLUSTER_LIST[@]}"; do
    log_info "${action}: ${cluster}"
    if ! minikube "${action}" -p "${cluster}"; then
      log_error "${action} failed for ${cluster}"
      failed=1
    fi
  done
  return "${failed}"
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

# Build minikube start arguments for a cluster into $reply
build_start_args() {
  local cluster=$1
  reply=(start "--kubernetes-version=${K8S_VERSION}" -p "${cluster}")

  if [[ -n "${CNI}" ]]; then
    reply+=("--cni=${CNI}")
  fi

  local service_cidr
  service_cidr="$(get_service_cidr "${cluster}")"
  if [[ -n "${service_cidr}" ]]; then
    reply+=("--service-cluster-ip-range=${service_cidr}")
  fi

  if [[ -n "${INSECURE_REGISTRIES}" ]]; then
    reply+=("--insecure-registry=${INSECURE_REGISTRIES}")
  fi
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
  minikube addons disable registry -p "${cluster}"
}

# Refresh the standalone kubeconfig for a started cluster.
sync_cluster_kubeconfig() {
  local cluster="$1"
  local config_dir="${HOME}/.kube/clusters"
  local config_file="${config_dir}/${cluster}"
  local temp_file

  mkdir -p -m 700 "${config_dir}"
  temp_file="$(mktemp "${config_file}.tmp.XXXXXX")"

  # Export only this cluster, including credentials, before replacing its file.
  if ! kubectl --context="${cluster}" config view --minify --flatten --raw > "${temp_file}"; then
    rm -f "${temp_file}"
    log_error "Failed to export kubeconfig for ${cluster}; ${config_file} was not changed."
    return 1
  fi

  chmod 600 "${temp_file}"
  mv -f "${temp_file}" "${config_file}"
  log_info "Updated kubeconfig: ${config_file}"
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

  local -a reply
  local cluster
  for cluster in "${CLUSTER_LIST[@]}"; do
    log_info "Starting cluster: ${cluster}"
    build_start_args "${cluster}"
    minikube "${reply[@]}"
    sync_cluster_kubeconfig "${cluster}"

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
  run_cluster_command stop
}

# Delete cluster(s)
delete_clusters() {
  log_warn "This will delete all data in: ${CLUSTERS}"
  local REPLY=""
  read -q "REPLY?Are you sure? (y/N): " || true
  echo
  if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
    log_info "Cancelled."
    return
  fi
  run_cluster_command delete
}

show_status() {
  run_cluster_command status
}

# Initialize metrics-server Helm repository
init_metrics_server() {
  log_info "Initializing metrics-server Helm repository..."
  helm repo add metrics-server "${METRICS_REPO}" --force-update
  helm repo update metrics-server
  log_info "Metrics-server repository initialized!"
}

# Install metrics-server
install_metrics_server() {
  log_info "Installing metrics-server..."
  
  init_metrics_server
  
  # Use first cluster for metrics-server installation
  local primary_cluster="${CLUSTER_LIST[1]}"
  
  log_info "Target cluster: ${primary_cluster}"
  
  # Install with default values for Minikube compatibility
  log_info "Installing with default values (kubelet-insecure-tls for Minikube compatibility)"
  helm upgrade --install "${METRICS_NAME}" metrics-server/metrics-server \
    --kube-context "${primary_cluster}" \
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
  
  local primary_cluster="${CLUSTER_LIST[1]}"
  
  log_info "Target cluster: ${primary_cluster}"
  
  helm uninstall "${METRICS_NAME}" --namespace "${METRICS_NAMESPACE}" \
    --kube-context "${primary_cluster}" --ignore-not-found
  
  log_info "Metrics-server uninstalled!"
}

# Handle `registry install|uninstall|port` for every profile.
registry_command() {
  local registry_cmd="$1" cluster ip
  local failed=0
  for cluster in "${CLUSTER_LIST[@]}"; do
    case "${registry_cmd}" in
      install) enable_registry_addon "${cluster}" || failed=1 ;;
      uninstall) disable_registry_addon "${cluster}" || failed=1 ;;
      port)
        if ip="$(minikube ip -p "${cluster}")" && [[ -n "${ip}" ]]; then
          printf '%s: %s:5000\n' "${cluster}" "${ip}"
        else
          log_error "Cannot get registry address for ${cluster}"
          failed=1
        fi
        ;;
    esac
  done
  return "${failed}"
}

# Only stable x.y.z versions are compared; never evaluate remote content.
is_stable_version() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

fetch_release_version() {
  local url="$1" format="${2:-text}" value
  value="$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 15 "$url")" || return 1
  if [[ "$format" == github ]]; then
    value="$(printf '%s' "$value" | jq -er 'select(.draft == false and .prerelease == false) | .tag_name')" || return 1
  fi
  is_stable_version "$value" || return 1
  printf '%s\n' "${value#v}"
}

report_release() {
  local label="$1" current="${2#v}" latest="${3#v}"
  if ! is_stable_version "$current"; then
    log_warn "${label}: current version unavailable/non-stable; latest stable ${latest}"
    return 1
  fi
  autoload -Uz is-at-least
  if [[ "$current" == "$latest" ]]; then
    log_info "${label}: ${current} (up to date)"
  elif is-at-least "$latest" "$current"; then
    log_info "${label}: ${current} (ahead of published stable ${latest})"
  else
    log_warn "UPDATE ${label}: ${current} -> ${latest}"
  fi
}

# Explicit, read-only network check. Does not access any Kubernetes context.
check_updates() {
  local tool current latest branch
  local failed=0
  for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_error "${tool} is required for updates."
      return 1
    fi
  done

  current=""
  if command -v minikube >/dev/null 2>&1; then
    current="$(minikube version --short)" || failed=1
  fi
  if latest="$(fetch_release_version https://api.github.com/repos/kubernetes/minikube/releases/latest github)"; then
    report_release "Minikube (installed)" "$current" "$latest" || failed=1
    log_info "Minikube release: https://github.com/kubernetes/minikube/releases/tag/v${latest}"
  else
    log_warn "Minikube: check unavailable (network, API limit or invalid response)."
    failed=1
  fi

  current="${K8S_VERSION#v}"
  log_info "Kubernetes configured for start: ${K8S_VERSION} (repository default: ${DEFAULT_K8S_VERSION})"
  if is_stable_version "$current"; then
    branch="${current%.*}"
    if latest="$(fetch_release_version "https://dl.k8s.io/release/stable-${branch}.txt")" && [[ "${latest%.*}" == "$branch" ]]; then
      report_release "Kubernetes ${branch} patch" "$current" "$latest" || failed=1
    else
      log_warn "Kubernetes ${branch}: patch check unavailable."
      failed=1
    fi
  else
    log_warn "Kubernetes: patch check requires K8S_VERSION=x.y.z (optional v prefix)."
    failed=1
  fi
  if latest="$(fetch_release_version https://dl.k8s.io/release/stable.txt)"; then
    report_release "Kubernetes latest stable" "$current" "$latest" || failed=1
  else
    log_warn "Kubernetes: latest stable check unavailable."
    failed=1
  fi
  log_info "Release notes: https://kubernetes.io/releases/"
  log_info "New Kubernetes releases may require a newer Minikube. No versions or clusters were changed."
  return "$failed"
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
  updates            Check Minikube and Kubernetes updates (requires curl + jq)
  metrics install    Install metrics-server
  metrics uninstall  Uninstall metrics-server
  registry install   Enable in-cluster registry addon
  registry uninstall Disable in-cluster registry addon
  registry port      Show host:port to reach the in-cluster registry
  help               Show this help message

Environment Variables:
  CLUSTERS            Comma-separated list of cluster names (default: ${DEFAULT_CLUSTERS})
  K8S_VERSION         Kubernetes version (default: ${DEFAULT_K8S_VERSION})
  CNI                 CNI plugin: cilium, calico, or empty for default (default: empty)
  SERVICE_CIDR        Service cluster IP range (default: auto-assigned)
  METRICS_SERVER      Install metrics-server on start: true/false (default: false)
  METRICS_VERSION     Metrics-server Helm chart version (default: ${DEFAULT_METRICS_VERSION})
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

  case "${command}" in
    help|--help|-h) show_usage; return ;;
    updates)
      if (( $# != 1 )); then
        log_error "updates does not accept arguments."
        return 1
      fi
      check_updates
      return
      ;;
    start|stop|delete|status)
      if (( $# != 1 )); then
        log_error "${command} does not accept arguments."
        return 1
      fi
      ;;
    metrics|registry)
      if (( $# != 2 )); then
        log_error "Invalid ${command} subcommand. See ${SCRIPT_NAME} help."
        return 1
      fi
      case "${command}:${2}" in
        metrics:install|metrics:uninstall|registry:install|registry:uninstall|registry:port) ;;
        *) log_error "Invalid ${command} subcommand. See ${SCRIPT_NAME} help."; return 1 ;;
      esac
      ;;
    *) show_usage; return 1 ;;
  esac
  validate_configuration

  if [[ "${command}" != metrics ]]; then
    ensure_installed minikube "https://minikube.sigs.k8s.io/docs/start/"
  fi
  if [[ "${command}" == start ]] && ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl is required to update per-cluster kubeconfig files. Please install it and re-run this script."
    return 1
  fi
  if [[ "${command}" == metrics || ( "${command}" == start && "${METRICS_SERVER}" == true ) ]]; then
    ensure_installed helm "https://helm.sh/docs/intro/install/"
  fi

  case "${command}" in
    start) start_clusters ;;
    stop) stop_clusters ;;
    delete) delete_clusters ;;
    status) show_status ;;
    metrics)
      case "$2" in
        install) install_metrics_server ;;
        uninstall) uninstall_metrics_server ;;
      esac
      ;;
    registry) registry_command "$2" ;;
  esac
}

# Run main function
main "$@"
