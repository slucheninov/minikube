#!/usr/bin/env bash

set -euo pipefail

# Configuration
readonly CHART_NAME="etcd"
readonly CHART_VERSION="12.0.18"
readonly NAMESPACE="coredns"
readonly HELM_REPO="bitnami"
readonly HELM_REPO_URL="https://charts.bitnami.com/bitnami"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MANIFESTS_DIR="${SCRIPT_DIR}/coredns-etcd"
readonly VALUES_DIR="${MANIFESTS_DIR}/values"
readonly SECRETS_FILE="${MANIFESTS_DIR}/secrets.yaml"

# Default values file
VALUES_FILE="${VALUES_DIR}/helm-values.yaml"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    init        Initialize Helm repository
    start       Deploy etcd cluster
    stop        Remove etcd cluster
    status      Check etcd cluster status
    help        Show this help message

Options:
    --no-auth   Use configuration without authentication (for start command)
    --values    Specify custom values file (for start command)

Examples:
    $0 init
    $0 start
    $0 start --no-auth
    $0 start --values /path/to/custom-values.yaml
    $0 stop
    $0 status

EOF
}

# Initialize Helm repository
cmd_init() {
    log_info "Initializing Helm repository..."
    helm repo add "${HELM_REPO}" "${HELM_REPO_URL}" || log_warn "Repository already exists"
    helm repo update
    log_info "Repository initialized successfully"
}

# Start etcd cluster
cmd_start() {
    log_info "Starting etcd cluster deployment..."

    # Check if values file exists
    if [[ ! -f "${VALUES_FILE}" ]]; then
        log_error "Values file not found: ${VALUES_FILE}"
        exit 1
    fi

    # Create namespace if it doesn't exist
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_info "Creating namespace: ${NAMESPACE}"
        kubectl create namespace "${NAMESPACE}"
    else
        log_info "Namespace ${NAMESPACE} already exists"
    fi

    # Apply secrets if they exist
    if [[ -f "${SECRETS_FILE}" ]]; then
        log_info "Applying secrets..."
        kubectl apply -f "${SECRETS_FILE}" -n "${NAMESPACE}"
        sleep 5
    else
        log_warn "Secrets file not found: ${SECRETS_FILE}"
    fi

    # Deploy etcd using Helm
    log_info "Deploying etcd chart (version: ${CHART_VERSION})..."
    helm upgrade --install "${CHART_NAME}" "${HELM_REPO}/etcd" \
        --version "${CHART_VERSION}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout 10m \
        --values "${VALUES_FILE}"

    log_info "etcd cluster deployed successfully"
    cmd_status
}

# Stop etcd cluster
cmd_stop() {
    log_warn "Stopping etcd cluster..."

    # Uninstall Helm release
    if helm list -n "${NAMESPACE}" | grep -q "${CHART_NAME}"; then
        log_info "Uninstalling Helm release: ${CHART_NAME}"
        helm uninstall "${CHART_NAME}" --namespace "${NAMESPACE}"
    else
        log_warn "Helm release ${CHART_NAME} not found"
    fi

    # Delete secrets if they exist
    if [[ -f "${SECRETS_FILE}" ]]; then
        log_info "Deleting secrets..."
        kubectl delete -f "${SECRETS_FILE}" -n "${NAMESPACE}" --ignore-not-found=true
    fi

    # Delete namespace
    log_info "Deleting namespace: ${NAMESPACE}"
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true

    log_info "etcd cluster stopped successfully"
}

# Check status
cmd_status() {
    log_info "Checking etcd cluster status..."

    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_warn "Namespace ${NAMESPACE} does not exist"
        return 1
    fi

    echo ""
    log_info "Helm release status:"
    helm list -n "${NAMESPACE}" | grep -E "NAME|${CHART_NAME}" || log_warn "No Helm releases found"

    echo ""
    log_info "Pods status:"
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=etcd

    echo ""
    log_info "Services:"
    kubectl get svc -n "${NAMESPACE}" -l app.kubernetes.io/name=etcd
}

# Parse options
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-auth)
                VALUES_FILE="${VALUES_DIR}/helm-values-no-auth.yaml"
                shift
                ;;
            --values)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing value for --values option"
                    exit 1
                fi
                VALUES_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        log_error "No command specified"
        show_help
        exit 1
    fi

    local command=$1
    shift

    case "${command}" in
        init)
            cmd_init
            ;;
        start)
            parse_args "$@"
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        status)
            cmd_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: ${command}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
