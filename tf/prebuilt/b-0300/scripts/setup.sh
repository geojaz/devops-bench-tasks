#!/usr/bin/env bash
# Setup for b-0300 "The missing ordinal". Runs from OUTSIDE
# the cluster during `tofu apply`, before the agent starts: applies the seed
# manifests (manifests/00-gating.yaml, then manifests/10-workloads.yaml, gating
# objects first and waited live before anything they gate is applied -- see
# compiler/manifest.py's GATING_KINDS) and asserts every seeded condition
# actually holds.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
INFRA_PROVIDER="${INFRA_PROVIDER:-kind}"

if [[ "${INFRA_PROVIDER}" == "gcp" ]]; then
  echo "==> Fetching GKE credentials for cluster ${CLUSTER_NAME:?} in project ${PROJECT_ID:?} (${LOCATION:?})"
  gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${LOCATION}" --project "${PROJECT_ID}"
fi

MANIFESTS_DIR="${MANIFESTS_DIR:?MANIFESTS_DIR is required}"
MANIFESTS_DIR="$(cd "${MANIFESTS_DIR}" && pwd)"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

# A vcluster kubeconfig secret can be populated before a cloud
# LoadBalancer has started forwarding to the virtual API server.
# Gate the first manifest apply on the endpoint itself, not merely
# on discovery of the credentials that point at it.
if [[ "${INFRA_PROVIDER}" == "vcluster" ]]; then
  echo "==> Waiting for the vcluster API endpoint..."
  _deadline=$((SECONDS+WAIT_TIMEOUT))
  until kubectl get --raw=/readyz >/dev/null 2>&1; do
    if (( SECONDS >= _deadline )); then
      echo "SETUP FAIL: vcluster API endpoint did not become ready within ${WAIT_TIMEOUT}s" >&2
      exit 1
    fi
    sleep 3
  done
fi

_ERRFILE="$(mktemp)"; trap 'rm -f "$_ERRFILE"' EXIT
guarded_read(){ local __v="$1"; shift; local __cmd="${1:-}" __out __rc=0; __out="$("$@" 2>"$_ERRFILE")" || __rc=$?; if [ "$__rc" -ne 0 ]; then if [ "$__cmd" = gcloud ]; then echo "CHECK ERROR: gcloud read failed ($*): $(cat "$_ERRFILE")" >&2; exit 1; fi; if grep -qE 'error parsing jsonpath|invalid array index|unable to parse|unrecognized|unknown flag|unknown command' "$_ERRFILE"; then echo "CHECK BUG: malformed kubectl query ($*): $(cat "$_ERRFILE")" >&2; exit 1; fi; fi; printf -v "$__v" '%s' "$__out"; }

echo "==> Applying gating manifests..."
envsubst '${CLUSTER_NAME}' < "${MANIFESTS_DIR}/00-gating.yaml" | kubectl apply -f -

echo "==> Applying workload manifests..."
envsubst '${CLUSTER_NAME}' < "${MANIFESTS_DIR}/10-workloads.yaml" | kubectl apply -f -

# assert seeded conditions actually hold at t0 (a seed that can't prove its
# conditions hold has failed before the experiment starts)
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val gcloud 'container' 'node-pools' 'describe' "${CLUSTER_NAME}" "--cluster=${HOST_CLUSTER_NAME}" "--location=${HOST_CLUSTER_LOCATION}" --project "${GCP_PROJECT_ID:-${PROJECT_ID:-}}" '--format=value(autoscaling.maxNodeCount)'
  [ "$val" = 1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SEED FAIL: gke-node-pool-max-nodes-set@${CLUSTER_NAME} not holding (gke-node-pool-max-nodes-set): timed out after ${WAIT_TIMEOUT}s -- cloud path autoscaling.maxNodeCount expected eq 1; last observed val='$val'"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get statefulset shipment-api -n "dispatch" -o jsonpath='{.status.readyReplicas}'
  [ "${val}" = 1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SEED FAIL: workload-ready-count@statefulset not holding (workload-ready-count): timed out after ${WAIT_TIMEOUT}s -- path status.readyReplicas expected to equal '1'; last observed value was '$val' (empty means the path was absent)"
    exit 1
  fi
  sleep 3
done

echo "==> Waiting for hold-mode rows and maintain-kind objectives to settle..."
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get statefulset shipment-api -n "dispatch" -o jsonpath='{.spec.template.spec.nodeSelector.devops-bench/run}'
  [ "${val}" = "${CLUSTER_NAME}" ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: workload-node-selector-set@statefulset did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get statefulset shipment-api -n "dispatch" -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[?(@.topologyKey == "kubernetes.io/hostname")].labelSelector.matchLabels.app}'
  [ "${val}" = shipment-api ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: workload-required-pod-affinity-set@statefulset did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment settlement-worker -n "dispatch" -o jsonpath='{.spec.template.spec.nodeSelector.devops-bench/run}'
  [ "${val}" = "${CLUSTER_NAME}" ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: workload-node-selector-set@deployment did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment settlement-worker -n "dispatch" -o jsonpath='{.spec.template.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution[?(@.topologyKey == "kubernetes.io/hostname")].labelSelector.matchLabels.statefulset\.kubernetes\.io/pod-name}'
  [ "${val}" = shipment-api-1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: workload-required-pod-affinity-set@deployment did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done

echo "==> Setup complete."
echo "    Seeded: b-0300 in dispatch."
echo "    Inspect: kubectl -n dispatch get all"
