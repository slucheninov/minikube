# coredns etcd migration and upgrade rehearsal

Lab for plich-115895: Bitnami etcd 9.8.1 (3.5.11) → own chart `infrastructure/charts-common/etcd`
→ 3.5.34 → 3.6.15 → 3.7.2 under client load, with rollbacks. The production runbook built from it lives in
brain: `infrastructure/brain/runbooks/coredns-etcd-upgrade.md`.

| File | Purpose |
|---|---|
| `tls.sh` | Test CA + one server/client cert with the prod SANs; Secret `etcd-main-tls` in `coredns`, `etcd-client-tls` in `etcd-load` and `corenet` |
| `values-bitnami.yaml` | Prod values (prod-stateful-1) without resources, affinity and storageClass; image `bitnamilegacy/etcd:3.5.11-debian-11-r3` |
| `values-chart.yaml` | The same values for the own chart; image tag via `--set image.tag=` |
| `loadgen/` | Go client (client/v3 3.6.10) + etcdctl/etcdutl 3.7.2 toolbox image `etcd-rehearsal:dev` |
| `loadgen.yaml` | `loadgen-svc` (ClusterIP endpoint), `loadgen-pods` (3 pod endpoints), `toolbox` |
| `corenet.yaml`, `corenet-job.yaml` | corenet `agent-k8s` (+ Service `demo`) and the static records Job (`-agent=cli`) |
| `rehearsal.sh` | `ctl`, `status`, `leader`, `snapshot`, `gate`, `stats [reset]`, `roll <pod> [--move-leader]` |

The load generator mimics the prod clients: `put` of SkyDNS records every 200 ms (corenet), prefix `get`
of `/skydns` every second, 4 lock workers with a session TTL 10s each (processing-core) and 4 leases with
TTL 2s renewed by `KeepAliveOnce` every second (shared-lock-api). Each operation has a 2s timeout.
`GET /stats` returns per operation `ok`/`err`, `lost` (session or lease expired), the longest outage
(last success before the first error to the next success) and the max latency; `POST /reset` starts a new window.
`rehearsal.sh roll` resets the window, deletes the pod, waits for the gate and prints the window.

## Setup

```bash
export KUBE_CONTEXT=cluster-1
CHART=../../tentens/infrastructure/charts-common/etcd    # local checkout or the OCI chart
helm pull etcd --repo https://charts.bitnami.com/bitnami --version 9.8.1 --untar -d /tmp/bitnami

scripts/etcd-rehearsal/tls.sh
helm --kube-context "$KUBE_CONTEXT" -n coredns install etcd /tmp/bitnami/etcd -f scripts/etcd-rehearsal/values-bitnami.yaml
(cd scripts/etcd-rehearsal/loadgen && docker build -t etcd-rehearsal:dev .)
minikube -p cluster-1 image load etcd-rehearsal:dev
kubectl --context "$KUBE_CONTEXT" apply -f scripts/etcd-rehearsal/loadgen.yaml
# corenet (scenario 7): build corenet-agent:dev in infrastructure/corenet, load it, then
kubectl --context "$KUBE_CONTEXT" apply -f scripts/etcd-rehearsal/corenet.yaml -f scripts/etcd-rehearsal/corenet-job.yaml
```

`tls.sh` keeps the CA in `.secrets/etcd-rehearsal/` and reuses it. For a second cluster in another namespace
pass `NAMESPACE=<ns> CLIENT_NAMESPACES= TLS_DIR=<other dir>`, otherwise the client Secrets get the other CA.

## Typical step

```bash
R=scripts/etcd-rehearsal/rehearsal.sh
$R snapshot before-step
helm --kube-context "$KUBE_CONTEXT" -n coredns upgrade etcd "$CHART" -f scripts/etcd-rehearsal/values-chart.yaml --set image.tag=v3.6.15
$R leader                          # followers first
$R roll etcd-0; $R roll etcd-2
$R roll etcd-1 --move-leader       # the leader last
$R status
```

Etcdctl in the official image works without a shell: `kubectl -n coredns exec etcd-0 -- etcdutl check v2store --data-dir /bitnami/etcd/data`.

## Cleanup

```bash
kubectl --context "$KUBE_CONTEXT" delete -f scripts/etcd-rehearsal/corenet-job.yaml -f scripts/etcd-rehearsal/corenet.yaml -f scripts/etcd-rehearsal/loadgen.yaml
helm --kube-context "$KUBE_CONTEXT" -n coredns uninstall etcd
kubectl --context "$KUBE_CONTEXT" -n coredns delete pvc data-etcd-0 data-etcd-1 data-etcd-2
kubectl --context "$KUBE_CONTEXT" delete namespace etcd-load corenet
```
