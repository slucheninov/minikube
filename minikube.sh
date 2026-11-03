#!/usr/bin/env zsh
#
# Personal wrapper over minikube: start cluster(s) with metrics-server and the
# registry addon, highlight new Minikube/Kubernetes releases, and pin versions
# with `./minikube.sh upgrade`. Versions are not stored in this script: they live
# in ~/.minikube.env (env vars override it). Run `./minikube.sh help` for details.
#
# Standalone: `./minikube.sh self install` copies it to ~/bin; no repo needed.
# Bump SCRIPT_VERSION (semver) on every change to this file.
#

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_PATH="${${(%):-%x}:A}"
readonly SCRIPT_NAME="$(basename "${(%):-%x}")"
readonly INSTALL_DIR="${HOME}/bin"
readonly INSTALL_NAME="minikube.sh"
readonly CONFIG_FILE="${HOME}/.minikube.env"
readonly -a CONFIG_KEYS=(CLUSTERS K8S_VERSION CNI SERVICE_CIDR METRICS_SERVER METRICS_VERSION
  REGISTRY INSECURE_REGISTRIES UPDATE_CHECK)
readonly METRICS_NAMESPACE="kube-system"
readonly METRICS_NAME="metrics-server"
readonly METRICS_REPO="https://kubernetes-sigs.github.io/metrics-server/"

readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'

log_info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_update() { echo -e "${YELLOW}[UPDATE]${NC} $1"; }

# Read KEY=VALUE lines from ~/.minikube.env (never sourced as code).
# Variables already set in the environment take precedence.
load_config() {
  [[ -f "${CONFIG_FILE}" ]] || return 0
  local line key value n=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( ++n ))
    [[ "${line}" =~ '^[[:space:]]*(#|$)' ]] && continue
    if [[ ! "${line}" =~ '^([A-Z0-9_]+)=(.*)$' ]]; then
      log_error "${CONFIG_FILE}:${n}: expected KEY=VALUE"
      return 1
    fi
    key="${match[1]}" value="${match[2]}"
    [[ "${value}" =~ '^"(.*)"$' || "${value}" =~ "^'(.*)'\$" ]] && value="${match[1]}"
    if (( ! ${CONFIG_KEYS[(Ie)${key}]} )); then
      log_warn "${CONFIG_FILE}:${n}: unknown key ${key} ignored"
      continue
    fi
    if [[ ! "${value}" =~ '^[A-Za-z0-9._,:/-]*$' ]]; then
      log_error "${CONFIG_FILE}:${n}: invalid value for ${key}"
      return 1
    fi
    (( ${+parameters[${key}]} )) || typeset -g "${key}=${value}"
  done < "${CONFIG_FILE}"
}

# Update KEY=VALUE pairs in ~/.minikube.env, keeping other lines (atomic).
write_config() {
  local -A new
  local kv line key tmp
  for kv in "$@"; do new[${kv%%=*}]="${kv#*=}"; done
  tmp="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")"
  {
    if [[ -f "${CONFIG_FILE}" ]]; then
      while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ '^([A-Z0-9_]+)=' ]] && (( ${+new[${match[1]}]} )); then
          key="${match[1]}"
          print -r -- "${key}=${new[${key}]}"
          unset "new[${key}]"
        else
          print -r -- "${line}"
        fi
      done < "${CONFIG_FILE}"
    else
      print -r -- "# ${SCRIPT_NAME} settings (KEY=VALUE). Env vars override; versions are set by '${SCRIPT_NAME} upgrade'."
    fi
    for key in ${(ok)new}; do print -r -- "${key}=${new[${key}]}"; done
  } > "${tmp}" || { rm -f "${tmp}"; return 1; }
  chmod 644 "${tmp}"
  mv -f "${tmp}" "${CONFIG_FILE}"
}

load_config

CLUSTERS="${CLUSTERS:-cluster-1}"
K8S_VERSION="${K8S_VERSION:-}"          # empty = minikube's default
CNI="${CNI:-}"
METRICS_SERVER="${METRICS_SERVER:-true}"
METRICS_VERSION="${METRICS_VERSION:-}"  # empty = latest chart
REGISTRY="${REGISTRY:-true}"
UPDATE_CHECK="${UPDATE_CHECK:-true}"
INSECURE_REGISTRIES="${INSECURE_REGISTRIES:-}"
typeset -ra CLUSTER_LIST=("${(@s:,:)CLUSTERS}")

# Fixed service CIDRs so multi-cluster setups don't overlap.
typeset -rA SERVICE_CIDR_MAP=(
  cluster-1 172.16.1.0/24
  cluster-2 172.16.2.0/24
  cluster-3 172.16.3.0/24
)

# In quiet mode (automatic check on start/status) only updates are printed.
UPDATES_QUIET=false
check_info() { [[ "${UPDATES_QUIET}" == true ]] || log_info "$1"; }
check_warn() { [[ "${UPDATES_QUIET}" == true ]] || log_warn "$1"; }

confirm() {
  local REPLY=""
  read -q "REPLY?$1 (y/N): " || true
  echo
  [[ "${REPLY}" =~ ^[Yy]$ ]]
}

# Only Homebrew is automated; never execute a downloaded installer.
ensure_installed() {
  local tool="$1" docs_url="$2"
  command -v "${tool}" >/dev/null 2>&1 && return 0
  log_error "${tool} is not installed. Installation guide: ${docs_url}"
  if [[ -t 0 ]] && command -v brew >/dev/null 2>&1 && confirm "Install ${tool} with Homebrew?"; then
    brew install "${tool}" && command -v "${tool}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Validate before invoking tools or using profile names as file paths.
validate_configuration() {
  local cluster flag
  local -A seen
  for cluster in "${CLUSTER_LIST[@]}"; do
    if [[ ! "${cluster}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
      log_error "Invalid cluster name: '${cluster}'. Use letters, digits, '_' and '-', starting with a letter or digit."
      return 1
    fi
    if [[ -n "${seen[$cluster]:-}" ]]; then
      log_error "Duplicate cluster name: ${cluster}"
      return 1
    fi
    seen[$cluster]=1
  done
  for flag in METRICS_SERVER REGISTRY UPDATE_CHECK; do
    if [[ "${(P)flag}" != true && "${(P)flag}" != false ]]; then
      log_error "${flag} must be true or false."
      return 1
    fi
  done
}

# Run `minikube <action>` for every profile; nonzero if any failed.
run_cluster_command() {
  local action="$1" cluster failed=0
  for cluster in "${CLUSTER_LIST[@]}"; do
    log_info "${action}: ${cluster}"
    minikube "${action}" -p "${cluster}" || { log_error "${action} failed for ${cluster}"; failed=1; }
  done
  return "${failed}"
}

# minikube start arguments for a cluster, returned in $reply.
build_start_args() {
  local cluster=$1
  local service_cidr="${SERVICE_CIDR:-${SERVICE_CIDR_MAP[$cluster]:-}}"
  reply=(start -p "${cluster}")
  [[ -n "${K8S_VERSION}" ]] && reply+=("--kubernetes-version=${K8S_VERSION}")
  [[ -n "${CNI}" ]] && reply+=("--cni=${CNI}")
  [[ -n "${service_cidr}" ]] && reply+=("--service-cluster-ip-range=${service_cidr}")
  [[ -n "${INSECURE_REGISTRIES}" ]] && reply+=("--insecure-registry=${INSECURE_REGISTRIES}")
  return 0
}

# Write a standalone kubeconfig to ~/.kube/clusters/<cluster> (atomic, mode 600).
sync_cluster_kubeconfig() {
  local cluster="$1" config_dir="${HOME}/.kube/clusters" temp_file
  local config_file="${config_dir}/${cluster}"
  mkdir -p -m 700 "${config_dir}"
  temp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
  if ! kubectl --context="${cluster}" config view --minify --flatten --raw > "${temp_file}"; then
    rm -f "${temp_file}"
    log_error "Failed to export kubeconfig for ${cluster}; ${config_file} was not changed."
    return 1
  fi
  chmod 600 "${temp_file}"
  mv -f "${temp_file}" "${config_file}"
  log_info "Updated kubeconfig: ${config_file}"
}

start_clusters() {
  log_info "Clusters: ${CLUSTERS} | Kubernetes: ${K8S_VERSION:-minikube default} | CNI: ${CNI:-default}"
  log_info "Metrics-server: ${METRICS_SERVER} | Registry: ${REGISTRY} | Insecure registries: ${INSECURE_REGISTRIES:-none}"

  local -a reply
  local cluster
  for cluster in "${CLUSTER_LIST[@]}"; do
    log_info "Starting cluster: ${cluster}"
    build_start_args "${cluster}"
    minikube "${reply[@]}"
    sync_cluster_kubeconfig "${cluster}"
    if [[ "${REGISTRY}" == true ]]; then
      minikube addons enable registry -p "${cluster}"
    fi
  done

  if [[ "${METRICS_SERVER}" == true ]]; then
    install_metrics_server
  fi
  run_cluster_command status || true
  auto_check_updates
}

delete_clusters() {
  log_warn "This will delete all data in: ${CLUSTERS}"
  if ! confirm "Are you sure?"; then
    log_info "Cancelled."
    return
  fi
  run_cluster_command delete
}

# metrics-server goes to the first cluster only, via explicit --kube-context.
install_metrics_server() {
  local cluster="${CLUSTER_LIST[1]}"
  local -a version_args=()
  [[ -n "${METRICS_VERSION}" ]] && version_args=(--version "${METRICS_VERSION}")
  log_info "Installing metrics-server ${METRICS_VERSION:-(latest chart)} on ${cluster}..."
  update_metrics_repo
  helm upgrade --install "${METRICS_NAME}" metrics-server/metrics-server \
    --kube-context "${cluster}" \
    "${version_args[@]}" \
    --namespace "${METRICS_NAMESPACE}" \
    --create-namespace \
    --wait \
    --set "args[0]=--kubelet-insecure-tls"
}

uninstall_metrics_server() {
  local cluster="${CLUSTER_LIST[1]}"
  log_info "Uninstalling metrics-server from ${cluster}..."
  helm uninstall "${METRICS_NAME}" --namespace "${METRICS_NAMESPACE}" \
    --kube-context "${cluster}" --ignore-not-found
}

# registry install|uninstall|port for every profile.
registry_command() {
  local cmd="$1" cluster ip failed=0
  for cluster in "${CLUSTER_LIST[@]}"; do
    case "${cmd}" in
      install)   minikube addons enable registry -p "${cluster}" || failed=1 ;;
      uninstall) minikube addons disable registry -p "${cluster}" || failed=1 ;;
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

# --- Versions ----------------------------------------------------------------
# Only stable x.y.z versions are compared; remote content is never evaluated.
is_stable_version() {
  [[ "$1" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+$' ]]
}

# True if $2 is a newer stable version than $1.
is_newer() {
  is_stable_version "$1" && is_stable_version "$2" || return 1
  autoload -Uz is-at-least
  ! is-at-least "${2#v}" "${1#v}"
}

fetch_release_version() {
  local url="$1" format="${2:-text}" value
  value="$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout "${CURL_CONNECT_TIMEOUT:-5}" --max-time "${CURL_MAX_TIME:-15}" "$url")" || return 1
  if [[ "$format" == github ]]; then
    value="$(printf '%s' "$value" | jq -er 'select(.draft == false and .prerelease == false) | .tag_name')" || return 1
  fi
  is_stable_version "$value" || return 1
  printf '%s\n' "${value#v}"
}

installed_minikube_version() {
  local v
  v="$(minikube version --short 2>/dev/null)" || return 1
  printf '%s\n' "${v#v}"
}

latest_minikube_version() {
  fetch_release_version https://api.github.com/repos/kubernetes/minikube/releases/latest github
}

# Newest stable Kubernetes supported by the installed minikube (offline).
supported_k8s_version() {
  minikube config defaults kubernetes-version -o json 2>/dev/null | jq -er '
    map(select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | ltrimstr("v"))
    | sort_by(split(".") | map(tonumber)) | last // empty'
}

update_metrics_repo() {
  helm repo add metrics-server "${METRICS_REPO}" --force-update >/dev/null
  helm repo update metrics-server >/dev/null
}

# Latest metrics-server chart from the local Helm repo cache.
latest_metrics_chart() {
  helm search repo metrics-server/metrics-server -o json 2>/dev/null | jq -er '.[0].version // empty'
}

# Read-only check; never touches clusters or changes versions.
check_updates() {
  local current="" latest supported chart failed=0
  local -a unpinned=()

  check_installed_copy

  current="$(installed_minikube_version)" || current=""
  if latest="$(latest_minikube_version)"; then
    if is_newer "${current}" "${latest}"; then
      log_update "Minikube ${current:-?} -> ${latest} (run '${SCRIPT_NAME} upgrade')"
    else
      check_info "Minikube ${current} (latest)"
    fi
  else
    check_warn "Minikube: release check unavailable (network, API limit or invalid response)."
    failed=1
  fi

  supported="$(supported_k8s_version)" || supported=""
  if [[ -z "${K8S_VERSION}" ]]; then
    unpinned+=(K8S_VERSION)
  elif is_newer "${K8S_VERSION}" "${supported}"; then
    log_update "Kubernetes ${K8S_VERSION#v} -> ${supported} (run '${SCRIPT_NAME} upgrade')"
  else
    check_info "Kubernetes ${K8S_VERSION} (newest supported by Minikube ${current}: ${supported:-unknown})"
  fi
  if [[ "${UPDATES_QUIET}" != true ]]; then
    if latest="$(fetch_release_version https://dl.k8s.io/release/stable.txt)"; then
      if is_newer "${supported}" "${latest}"; then
        log_info "Kubernetes ${latest} is released; it needs a newer Minikube (current supports up to ${supported})."
      fi
    else
      log_warn "Kubernetes: latest stable check unavailable."
      failed=1
    fi
  fi

  if command -v helm >/dev/null 2>&1; then
    # Quiet mode uses the local Helm cache only.
    [[ "${UPDATES_QUIET}" == true ]] || update_metrics_repo 2>/dev/null || failed=1
    if chart="$(latest_metrics_chart)"; then
      if [[ -z "${METRICS_VERSION}" ]]; then
        unpinned+=(METRICS_VERSION)
      elif is_newer "${METRICS_VERSION}" "${chart}"; then
        log_update "metrics-server chart ${METRICS_VERSION} -> ${chart} (run '${SCRIPT_NAME} upgrade')"
      else
        check_info "metrics-server chart ${METRICS_VERSION} (latest)"
      fi
    fi
  fi

  if (( ${#unpinned} )); then
    log_warn "Not pinned: ${unpinned[*]}; see '${SCRIPT_NAME} upgrade'."
  fi
  return "$failed"
}

# Automatic check after start/status: short timeouts, only highlights updates,
# never fails the command. Disable with UPDATE_CHECK=false.
auto_check_updates() {
  [[ "${UPDATE_CHECK}" == true ]] || return 0
  command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  if ! UPDATES_QUIET=true CURL_CONNECT_TIMEOUT=3 CURL_MAX_TIME=5 check_updates 2>/dev/null; then
    log_warn "Update check incomplete; run '${SCRIPT_NAME} updates' for details."
  fi
  return 0
}

# --- upgrade ------------------------------------------------------------------
# `upgrade` only prints a plan; ~/.minikube.env changes only via an explicit
# `upgrade k8s|metrics|all` (backup in ~/.minikube.env.bak). Pins are never
# lowered and clusters are never touched.

# Proposed pins: sets TARGET_K8S / TARGET_METRICS (empty = unknown).
TARGET_K8S="" TARGET_METRICS=""
resolve_targets() {
  local want="$1" supported chart
  if [[ "${want}" == k8s || "${want}" == all ]]; then
    if supported="$(supported_k8s_version)"; then
      TARGET_K8S="${supported}"
      if [[ -n "${K8S_VERSION}" ]] && ! is_newer "${K8S_VERSION}" "${supported}"; then TARGET_K8S="${K8S_VERSION#v}"; fi
    else
      log_error "Cannot read Kubernetes versions supported by Minikube."
    fi
  fi
  if [[ "${want}" == metrics || "${want}" == all ]]; then
    if update_metrics_repo && chart="$(latest_metrics_chart)"; then
      TARGET_METRICS="${chart}"
      if [[ -n "${METRICS_VERSION}" ]] && ! is_newer "${METRICS_VERSION}" "${chart}"; then TARGET_METRICS="${METRICS_VERSION}"; fi
    else
      log_error "Cannot find the latest metrics-server chart."
    fi
  fi
}

# Print "KEY: old -> new" lines; returns 1 if nothing would change.
print_plan() {
  local changed=1
  if [[ -n "${TARGET_K8S}" ]]; then
    if [[ "${TARGET_K8S}" != "${K8S_VERSION#v}" ]]; then
      log_update "K8S_VERSION: ${K8S_VERSION:-unpinned} -> ${TARGET_K8S}"; changed=0
    else
      log_info "K8S_VERSION: ${K8S_VERSION} (up to date)"
    fi
  fi
  if [[ -n "${TARGET_METRICS}" ]]; then
    if [[ "${TARGET_METRICS}" != "${METRICS_VERSION}" ]]; then
      log_update "METRICS_VERSION: ${METRICS_VERSION:-unpinned} -> ${TARGET_METRICS}"; changed=0
    else
      log_info "METRICS_VERSION: ${METRICS_VERSION} (up to date)"
    fi
  fi
  return "${changed}"
}

warn_env_override() {
  local key
  for key in "$@"; do
    if [[ -n "${(P)key}" && -f "${CONFIG_FILE}" ]] && ! grep -q "^${key}=" "${CONFIG_FILE}"; then
      log_warn "${key} is set in the environment; it will still override ${CONFIG_FILE}."
    fi
  done
}

upgrade_plan() {
  local current latest
  current="$(installed_minikube_version)" || current=""
  if latest="$(latest_minikube_version)"; then
    if is_newer "${current}" "${latest}"; then
      log_update "Minikube ${current} -> ${latest} (apply: ${SCRIPT_NAME} upgrade minikube)"
    else
      log_info "Minikube ${current} (latest)"
    fi
  else
    log_warn "Minikube: release check unavailable."
  fi
  resolve_targets all
  if print_plan; then
    log_info "Nothing written. Apply with: ${SCRIPT_NAME} upgrade k8s|metrics|all"
  else
    log_info "${CONFIG_FILE} is up to date."
  fi
}

upgrade_apply() {
  local want="$1"
  local -a pairs=() keys=()
  resolve_targets "${want}"
  [[ -n "${TARGET_K8S}${TARGET_METRICS}" ]] || return 1
  if ! print_plan; then
    log_info "${CONFIG_FILE} is up to date."
    return 0
  fi
  [[ -n "${TARGET_K8S}" && "${TARGET_K8S}" != "${K8S_VERSION#v}" ]] && { pairs+=("K8S_VERSION=${TARGET_K8S}"); keys+=(K8S_VERSION); }
  [[ -n "${TARGET_METRICS}" && "${TARGET_METRICS}" != "${METRICS_VERSION}" ]] && { pairs+=("METRICS_VERSION=${TARGET_METRICS}"); keys+=(METRICS_VERSION); }
  if [[ -t 0 ]] && ! confirm "Write ${keys[*]} to ${CONFIG_FILE}?"; then
    log_info "Cancelled; nothing written."
    return 0
  fi
  if [[ -f "${CONFIG_FILE}" ]]; then
    cp -p "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
    log_info "Backup: ${CONFIG_FILE}.bak"
  fi
  warn_env_override "${keys[@]}"
  write_config "${pairs[@]}"
  log_info "Saved ${keys[*]} to ${CONFIG_FILE} (other lines kept)."
  (( ${keys[(Ie)K8S_VERSION]} )) && log_info "Apply Kubernetes: ${SCRIPT_NAME} start (upgrades existing clusters in place)."
  (( ${keys[(Ie)METRICS_VERSION]} )) && log_info "Apply metrics-server: ${SCRIPT_NAME} metrics install"
  return 0
}

# Minikube itself: Homebrew only, with confirmation in a terminal.
upgrade_minikube() {
  local current latest
  current="$(installed_minikube_version)" || current=""
  if ! latest="$(latest_minikube_version)"; then
    log_error "Minikube: release check unavailable."
    return 1
  fi
  if ! is_newer "${current}" "${latest}"; then
    log_info "Minikube ${current} (latest)"
    return 0
  fi
  if [[ ! -t 0 ]] || ! command -v brew >/dev/null 2>&1 || ! brew list --formula minikube >/dev/null 2>&1; then
    log_update "Minikube ${current} -> ${latest}: not managed by Homebrew here; upgrade it with your package manager."
    return 1
  fi
  confirm "Upgrade Minikube ${current} -> ${latest} with Homebrew?" || { log_info "Cancelled."; return 0; }
  brew upgrade minikube
  log_info "Then check Kubernetes: ${SCRIPT_NAME} upgrade"
}

# --- self ---------------------------------------------------------------------
# Version of a copy of this script, read as text (the file is never executed).
script_version_of() {
  local line
  line="$(grep -m1 '^readonly SCRIPT_VERSION=' "$1" 2>/dev/null)" || return 1
  line="${${line#*=}//\"/}"
  is_stable_version "${line}" || return 1
  print -r -- "${line}"
}

# Highlight an outdated ~/bin copy when running another copy (e.g. the repo).
check_installed_copy() {
  local target="${INSTALL_DIR}/${INSTALL_NAME}" installed
  [[ -f "${target}" && "${target:A}" != "${SCRIPT_PATH}" ]] || return 0
  installed="$(script_version_of "${target}")" || return 0
  if is_newer "${installed}" "${SCRIPT_VERSION}"; then
    log_update "${target} ${installed} -> ${SCRIPT_VERSION} (run '${SCRIPT_NAME} self install')"
  fi
}

# Copy this script to <dir>/minikube.sh (default ~/bin): atomic, mode 755,
# previous copy kept as .bak. Refuses to overwrite a file that is not this script.
self_install() {
  local dir="${1:-${INSTALL_DIR}}" target installed
  dir="${dir:A}"
  target="${dir}/${INSTALL_NAME}"
  if [[ "${target}" == "${SCRIPT_PATH}" ]]; then
    log_info "${target} is the running copy (${SCRIPT_VERSION}); nothing to do."
    return 0
  fi
  if [[ -e "${target}" ]]; then
    if ! installed="$(script_version_of "${target}")"; then
      log_error "${target} exists and is not a versioned ${INSTALL_NAME}; not overwriting."
      return 1
    fi
    if [[ "${installed}" == "${SCRIPT_VERSION}" ]] && cmp -s "${SCRIPT_PATH}" "${target}"; then
      log_info "${target} is up to date (${SCRIPT_VERSION})."
      return 0
    fi
    if is_newer "${SCRIPT_VERSION}" "${installed}"; then
      log_warn "${target} ${installed} is newer than this copy ${SCRIPT_VERSION}."
      if [[ ! -t 0 ]] || ! confirm "Downgrade it?"; then
        log_info "Cancelled."
        return 1
      fi
    elif [[ "${installed}" == "${SCRIPT_VERSION}" ]]; then
      log_warn "${target} has the same version ${installed} but different content."
      if [[ -t 0 ]] && ! confirm "Replace it?"; then log_info "Cancelled."; return 0; fi
    else
      log_update "${target}: ${installed} -> ${SCRIPT_VERSION}"
      if [[ -t 0 ]] && ! confirm "Replace it?"; then log_info "Cancelled."; return 0; fi
    fi
  fi

  local tmp
  mkdir -p "${dir}"
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  if ! cp "${SCRIPT_PATH}" "${tmp}"; then rm -f "${tmp}"; return 1; fi
  chmod 755 "${tmp}"
  if [[ -e "${target}" ]]; then
    cp -p "${target}" "${target}.bak"
    log_info "Backup: ${target}.bak"
  fi
  mv -f "${tmp}" "${target}"
  log_info "Installed ${target} (${SCRIPT_VERSION})."
  if (( ! ${${path:A}[(Ie)${dir}]} )); then
    log_warn "${dir} is not in PATH; add to ~/.zshrc: export PATH=\"${dir}:\$PATH\""
  fi
}

self_uninstall() {
  local dir="${1:-${INSTALL_DIR}}" target installed
  target="${dir:A}/${INSTALL_NAME}"
  if [[ ! -e "${target}" ]]; then
    log_info "${target} is not installed."
    return 0
  fi
  if ! installed="$(script_version_of "${target}")"; then
    log_error "${target} is not a versioned ${INSTALL_NAME}; not removing."
    return 1
  fi
  if [[ -t 0 ]] && ! confirm "Remove ${target} (${installed})?"; then
    log_info "Cancelled."
    return 0
  fi
  rm -f "${target}" "${target}.bak"
  log_info "Removed ${target}. ${CONFIG_FILE} is kept."
}

show_usage() {
  cat << EOF
${SCRIPT_NAME} ${SCRIPT_VERSION}

Usage: ${SCRIPT_NAME} <command>

Commands:
  start | stop | status   Manage cluster(s)
  delete                  Delete cluster(s) (asks for confirmation)
  updates                 Show available Minikube/Kubernetes/metrics-server updates
  upgrade                 Show planned version changes (writes nothing)
  upgrade k8s|metrics|all Pin newest versions in ~/.minikube.env (asks; backup .bak)
  upgrade minikube        brew upgrade minikube (asks)
  metrics install|uninstall           metrics-server on the first cluster
  registry install|uninstall|port     Registry addon / print host:port
  self install|uninstall [dir]        Copy this script to dir/minikube.sh (default ~/bin)
  version                 Print the script version
  help                    Show this help

Settings (env vars, or KEY=VALUE lines in ~/.minikube.env; env wins):
  CLUSTERS             Comma-separated cluster names (default: cluster-1)
  K8S_VERSION          Kubernetes version (default: minikube's default; pinned by upgrade)
  CNI                  cilium, calico, or empty for default
  SERVICE_CIDR         Service IP range for all clusters (default: per-cluster map)
  METRICS_SERVER       Install metrics-server on start: true/false (default: true)
  METRICS_VERSION      metrics-server chart version (default: latest; pinned by upgrade)
  REGISTRY             Enable registry addon on start: true/false (default: true)
  INSECURE_REGISTRIES  Comma-separated plain-HTTP registries to trust (set at node creation)
  UPDATE_CHECK         Highlight new Minikube/Kubernetes after start/status (default: true)

Examples:
  ${SCRIPT_NAME} upgrade && ${SCRIPT_NAME} upgrade all && ${SCRIPT_NAME} start
  CLUSTERS="cluster-1,cluster-2" CNI=cilium ${SCRIPT_NAME} start
  METRICS_SERVER=false REGISTRY=false ${SCRIPT_NAME} start
EOF
}

main() {
  local command="${1:-}"

  case "${command}" in
    help|--help|-h) show_usage; return ;;
    version|--version|-V)
      (( $# == 1 )) || { log_error "version does not accept arguments."; return 1; }
      print -r -- "${SCRIPT_NAME} ${SCRIPT_VERSION}"
      return
      ;;
    self)
      case "${2:-}:$#" in
        install:2|install:3) self_install "${3:-}"; return ;;
        uninstall:2|uninstall:3) self_uninstall "${3:-}"; return ;;
        *) log_error "Invalid self subcommand. See ${SCRIPT_NAME} help."; return 1 ;;
      esac
      ;;
    start|stop|delete|status|updates)
      if (( $# != 1 )); then
        log_error "${command} does not accept arguments."
        return 1
      fi
      ;;
    upgrade)
      case "${2:-plan}:$#" in
        plan:1|plan:2|k8s:2|metrics:2|all:2|minikube:2) ;;
        *) log_error "Invalid upgrade subcommand. See ${SCRIPT_NAME} help."; return 1 ;;
      esac
      ;;
    metrics|registry)
      case "${command}:${2:-}:$#" in
        metrics:install:2|metrics:uninstall:2|registry:install:2|registry:uninstall:2|registry:port:2) ;;
        *) log_error "Invalid ${command} subcommand. See ${SCRIPT_NAME} help."; return 1 ;;
      esac
      ;;
    *) show_usage; return 1 ;;
  esac

  if [[ "${command}" == updates || "${command}" == upgrade ]]; then
    local tool
    for tool in curl jq; do
      command -v "${tool}" >/dev/null 2>&1 || { log_error "${tool} is required for ${command}."; return 1; }
    done
    ensure_installed minikube "https://minikube.sigs.k8s.io/docs/start/"
    if [[ "${command}" == upgrade ]]; then
      case "${2:-plan}" in
        minikube) upgrade_minikube; return ;;
        k8s) ;;
        *) ensure_installed helm "https://helm.sh/docs/intro/install/" ;;
      esac
      case "${2:-plan}" in
        plan) upgrade_plan ;;
        *) upgrade_apply "$2" ;;
      esac
    else
      check_updates
    fi
    return
  fi

  validate_configuration
  if [[ "${command}" != metrics ]]; then
    ensure_installed minikube "https://minikube.sigs.k8s.io/docs/start/"
  fi
  if [[ "${command}" == start ]] && ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl is required to export per-cluster kubeconfig files."
    return 1
  fi
  if [[ "${command}" == metrics || ( "${command}" == start && "${METRICS_SERVER}" == true ) ]]; then
    ensure_installed helm "https://helm.sh/docs/intro/install/"
  fi

  case "${command}" in
    start) start_clusters ;;
    stop) run_cluster_command stop ;;
    delete) delete_clusters ;;
    status)
      local rc=0
      run_cluster_command status || rc=$?
      auto_check_updates
      return "${rc}"
      ;;
    metrics)
      if [[ "$2" == install ]]; then install_metrics_server; else uninstall_metrics_server; fi
      ;;
    registry) registry_command "$2" ;;
  esac
}

main "$@"
