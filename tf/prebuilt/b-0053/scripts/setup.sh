#!/usr/bin/env bash
# Setup for b-0053 "The capped GKE node pool: approved pods outgrow an autoscaling ceiling". Runs from OUTSIDE
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
  gcloud container clusters get-credentials "${CLUSTER_NAME}" --location "${LOCATION}" --project "${PROJECT_ID}"
fi

MANIFESTS_DIR="${MANIFESTS_DIR:?MANIFESTS_DIR is required}"
MANIFESTS_DIR="$(cd "${MANIFESTS_DIR}" && pwd)"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

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
  guarded_read val gcloud 'container' 'node-pools' 'describe' 'primary-node-pool' "--cluster=${CLUSTER_NAME}" '--location=us-east1-d' --project "${GCP_PROJECT_ID:-${PROJECT_ID:-}}" '--format=value(autoscaling.maxNodeCount)'
  [ "$val" = 1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SEED FAIL: gke-node-pool-max-nodes-set@primary-node-pool not holding (gke-node-pool-max-nodes-set): timed out after ${WAIT_TIMEOUT}s -- cloud path autoscaling.maxNodeCount expected eq 1; last observed val='$val'"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment shipment-api -n "dispatch" -o jsonpath='{.status.readyReplicas}'
  [ "${val}" = 1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SEED FAIL: pod-ready@shipment.wl not holding (pod-ready): timed out after ${WAIT_TIMEOUT}s -- path status.readyReplicas expected to equal '1'; last observed value was '$val' (empty means the path was absent)"
    exit 1
  fi
  sleep 3
done

echo "==> Waiting for hold-mode rows and maintain-kind objectives to settle..."
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment shipment-api -n "dispatch" -o jsonpath='{.spec.template.spec.containers[?(@.name == "web")].resources.requests.cpu}'
  [ "${val}" = 700m ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: resource-request-set@shipment.wl did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment catalog-api -n "dispatch" -o jsonpath='{.spec.template.spec.containers[?(@.name == "web")].resources.requests.cpu}'
  [ "${val}" = 100m ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: resource-request-set@catalog.wl did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment shipment-api -n "dispatch" -o jsonpath='{.spec.replicas}'
  [ "${val}" = 2 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: workload-replicas-scaled@shipment.wl did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment catalog-api -n "dispatch" -o jsonpath='{.spec.replicas}'
  [ "${val}" = 1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: workload-replicas-scaled@catalog.wl did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done
_deadline=$((SECONDS+$WAIT_TIMEOUT))
while :; do
  guarded_read val kubectl get deployment catalog-api -n "dispatch" -o jsonpath='{.status.readyReplicas}'
  [ -n "$val" ] && [ "$val" -ge 1 ] && break
  if (( SECONDS >= _deadline )); then
    echo "SETTLE FAIL: ready-floor-held@deployment did not reach its t0-true state within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 3
done

echo "==> Setup complete."
echo "    Seeded: b-0053 in dispatch."
echo "    Inspect: kubectl -n dispatch get all"
