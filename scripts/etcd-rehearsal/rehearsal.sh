#!/usr/bin/env bash
# Helpers for the coredns etcd migration/upgrade rehearsal (see README.md in this directory).
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:?Set KUBE_CONTEXT to the intended lab cluster}"
NAMESPACE="${NAMESPACE:-coredns}"
LOAD_NAMESPACE="${LOAD_NAMESPACE:-etcd-load}"
GATE_TIMEOUT="${GATE_TIMEOUT:-300}"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
k() { kubectl --context="$KUBE_CONTEXT" "$@"; }
ke() { k -n "$NAMESPACE" "$@"; }

# etcdctl 3.7 from the toolbox pod; ETCDCTL_ENDPOINTS lists the members 0..2.
ctl() { k -n "$LOAD_NAMESPACE" exec deploy/toolbox -- etcdctl "$@"; }
ctl_env() { local eps="$1"; shift; k -n "$LOAD_NAMESPACE" exec deploy/toolbox -- env ETCDCTL_ENDPOINTS="$eps" etcdctl "$@"; }
# All member client URLs from `member list` (covers scale-up beyond 3).
endpoints() { ctl member list -w json | jq -r '[.members[] | select(.clientURLs) | .clientURLs[0]] | join(",")'; }
ctl_all() { ctl_env "$(endpoints)" "$@"; }

usage() {
  cat <<EOF
Usage: KUBE_CONTEXT=<ctx> $0 <command>
  ctl <etcdctl args>   etcdctl in the toolbox pod
  status               pods (image, preStop), member list, endpoint status
  leader               name of the leader pod
  snapshot <name>      etcdctl snapshot save from the first member into the toolbox /tmp/<name>.db
  gate                 wait until all members started, pods Ready, raft index equal, no alarms
  stats [reset]        loadgen counters and outages since the last reset
  roll <pod> [--move-leader]
                       reset stats, delete the pod, wait for the gate, print outages
EOF
  exit 1
}

status() {
  ke get pods -l app.kubernetes.io/name=etcd -o json | jq -r '.items[] |
    [.metadata.name, (.status.containerStatuses[0].ready|tostring), .spec.containers[0].image,
     (if .spec.containers[0].lifecycle.preStop then "preStop" else "-" end),
     (.status.containerStatuses[0].restartCount|tostring)] | @tsv' |
    (printf 'POD\tREADY\tIMAGE\tHOOK\tRESTARTS\n'; cat) | column -t
  ctl member list -w table
  ctl_all endpoint status -w table
}

leader() {
  ctl_all endpoint status -w json | jq -r '.[] | select(.Status.leader == .Status.header.member_id) | .Endpoint' |
    sed -E 's#https://([^.]+)\..*#\1#'
}

snapshot() {
  local name="${1:?snapshot name required}"
  ctl_env "$(endpoints | cut -d, -f1)" snapshot save "/tmp/$name.db" >/dev/null 2>&1
  k -n "$LOAD_NAMESPACE" exec deploy/toolbox -- etcdutl snapshot status "/tmp/$name.db" -w table
}

gate_once() {
  local members status
  members=$(ctl member list -w json) || return 1
  # Started voting members (a learner or an unstarted member has no name / is learner).
  jq -e '[.members[] | select((.name // "") == "" or .isLearner == true)] | length == 0' <<<"$members" >/dev/null || return 1
  local want
  want=$(jq '.members | length' <<<"$members")
  [[ "$(ke get pods -l app.kubernetes.io/name=etcd -o json |
        jq '[.items[] | select(.status.containerStatuses[0].ready == true)] | length')" == "$want" ]] || return 1
  status=$(ctl_all endpoint status -w json) || return 1
  jq -e --argjson n "$want" 'length == $n and ([.[].Status.raftAppliedIndex] | max - min) <= 5' <<<"$status" >/dev/null || return 1
  [[ -z "$(ctl alarm list)" ]] || return 1
}

gate() {
  local deadline=$((SECONDS + GATE_TIMEOUT))
  until gate_once 2>/dev/null; do
    ((SECONDS < deadline)) || fail "gate not passed in ${GATE_TIMEOUT}s"
    sleep 2
  done
  log "gate passed"
}

loadgen_pods() { k -n "$LOAD_NAMESPACE" get pods -l role=loadgen -o jsonpath='{range .items[*]}{.metadata.labels.app}={.status.podIP}{"\n"}{end}'; }

stats() {
  local name ip
  while IFS='=' read -r name ip; do
    if [[ "${1:-}" == reset ]]; then
      k -n "$LOAD_NAMESPACE" exec deploy/toolbox -- curl -sf -X POST "http://$ip:8080/reset"
    else
      k -n "$LOAD_NAMESPACE" exec deploy/toolbox -- curl -sf "http://$ip:8080/stats" | jq -c --arg n "$name" '{client: $n, seconds: (.seconds|floor),
        ops: (.ops | map_values({ok, err, lost: (.lost // 0), max_outage_s: ((.max_outage_s*100|round)/100), max_latency_s: ((.max_latency_s*100|round)/100)})),
        outages: [(.outages // [])[] | {op, worker, s: ((.seconds*100|round)/100), err: .last_error[0:80]}],
        ongoing: [(.ongoing // [])[] | {op, s: (.seconds|floor)}]}'
    fi
  done < <(loadgen_pods)
}

roll() {
  local pod="${1:?pod name required}" move="${2:-}" lead target
  gate
  lead=$(leader)
  if [[ "$move" == --move-leader && "$lead" == "$pod" ]]; then
    # Hex IDs straight from etcdctl: member IDs exceed int64, printf %x would overflow.
    target=$(ctl member list -w json --hex | jq -r --arg p "$pod" '[.members[] | select(.name != $p and .isLearner != true)][0].ID')
    log "move-leader $pod -> $target"
    ctl_all move-leader "$target"
  fi
  stats reset
  log "delete pod $pod (leader before: $lead)"
  local t0=$SECONDS
  ke delete pod "$pod" --wait=true
  log "pod gone after $((SECONDS - t0))s"
  ke wait --for=condition=Ready "pod/$pod" --timeout="${GATE_TIMEOUT}s"
  log "pod Ready after $((SECONDS - t0))s"
  gate
  log "gate after $((SECONDS - t0))s"
  sleep 5
  log "leader after: $(leader)"
  stats
}

cmd="${1:-}"
[[ -n "$cmd" ]] || usage
shift
case "$cmd" in
  ctl) ctl "$@" ;;
  status) status ;;
  leader) leader ;;
  snapshot) snapshot "$@" ;;
  gate) gate ;;
  stats) stats "$@" ;;
  roll) roll "$@" ;;
  *) usage ;;
esac
