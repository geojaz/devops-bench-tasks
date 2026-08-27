#!/usr/bin/env bash
# b-0060 control: oracle.
# Two real faults, mirroring b-0057's shape but with the mechanics inverted:
#   1. billing-sync-config's ConfigMap (data.replicas) was corrupted from
#      "3" to "0", and billing-sync-worker's own Deployment (poll cadence
#      ~20s, in the billing-sync namespace, not notifications-sync) already
#      enforced it onto notifications-sync-web before the agent started.
#      Unchanged from b-0057/b-0056.
#   2. notifications-sync-indexer's per-pod requests.memory was inflated
#      from 12Mi to 40Mi (limits.memory 24Mi -> 80Mi in lockstep, purely to
#      satisfy the requests <= limits admission invariant) against the
#      pre-existing zero-slack notifications-sync-compute ResourceQuota
#      (requests.memory hard: 400Mi). Unlike b-0057's backend inflation,
#      this produces NO symptom before the agent acts: while
#      notifications-sync-web sits at 0, deploy-runner's periodic
#      `rollout restart` of the indexer always has enough headroom to admit.
#      Only after this control's own ConfigMap fix restores web to 3/3 and
#      consumes that headroom does the indexer's next persona-triggered
#      restart threaten to wedge on quota admission (see task/GRADING.md's
#      arithmetic section).
#
# Because this control fixes the ConfigMap FIRST and only then right-sizes
# the indexer, the mirror image of b-0057's problem appears: at the moment
# the indexer patch lands, web is already at 3 x 61Mi = 183Mi, the indexer
# itself still holds 3 x 40Mi = 120Mi, backend holds its fixed 3 x 23Mi =
# 69Mi, and deploy-runner holds its own fixed 4Mi, for 183+120+69+4 = 376Mi
# of the 400Mi quota in use (see task/GRADING.md for the precise
# reconciliation), leaving 24Mi of slack against the 400Mi hard cap. A
# rolling update's surge pod at the indexer's NEW (small, right-sized) 12Mi
# request fits comfortably inside that 24Mi with margin to spare (even
# counting the transient peak while the 3 OLD fat pods are still up
# alongside the 1 new surge pod: 183+69+120+12+4 = 388Mi, still <= 400Mi),
# so unlike b-0057's backend (where the surge pod was the FAT one and a
# scale-to-0/patch/scale-back bounce was required to avoid a wedge), a
# single plain in-place `kubectl patch` on the running indexer Deployment is
# sufficient here: no bounce needed, and no retry-loop dependency either.
# deploy-runner's requests.memory stays 4Mi for the quota arithmetic (see
# tf/prebuilt/b-0060/manifests/notifications-sync.yaml), while its
# limits.memory is 96Mi so kubectl can actually run: limits are not
# quota-relevant, and this margin exists cleanly rather than requiring the
# oracle to tolerate a transient admission retry.
#
# After patching, this control waits out one full deploy-runner cadence
# (90s) plus margin to positively confirm the indexer's Progressing
# condition HOLDS status=True through at least one more persona-triggered
# restart, not just that the patch was accepted, then independently
# confirms the persona itself actually fired a successful restart by
# grepping deploy-runner's own logs, so a functionally dead persona cannot
# make the status-based check pass vacuously. Expected score: 1.0 with
# every safeguard held.
set -euo pipefail
echo "context: $(kubectl config current-context)"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"
readonly INDEXER_ORIG_MEM="12Mi"
readonly INDEXER_ORIG_LIMIT_MEM="24Mi"
readonly FINAL_HOLD_SEC=150
readonly FINAL_HOLD_POLL_SEC=10

echo "oracle: repair 1/2 -- restoring billing-sync-config's data.replicas to 3..."
kubectl patch configmap billing-sync-config -n billing-sync --type=merge \
  -p '{"data":{"replicas":"3"}}'

echo "oracle: waiting for notifications-sync-web to report 3 ready replicas (covers billing-sync-worker's next poll and the resulting rollout)..."
_deadline=$((SECONDS+WAIT_TIMEOUT))
while :; do
  _ready="$(kubectl get deployment notifications-sync-web -n notifications-sync -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [ "${_ready}" = "3" ]; then
    break
  fi
  if (( SECONDS >= _deadline )); then
    echo "oracle: FAILED, notifications-sync-web did not report 3 ready replicas within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 5
done

echo "oracle: repair 2/2 -- right-sizing notifications-sync-indexer's requests.memory back to ${INDEXER_ORIG_MEM} and limits.memory back to ${INDEXER_ORIG_LIMIT_MEM} via a plain in-place patch (the surge pod at the new small request size fits the remaining quota slack, no scale-to-0 bounce needed)..."
kubectl patch deployment notifications-sync-indexer -n notifications-sync --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/memory\",\"value\":\"${INDEXER_ORIG_MEM}\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits/memory\",\"value\":\"${INDEXER_ORIG_LIMIT_MEM}\"}]"

echo "oracle: waiting for notifications-sync-indexer's rollout to complete..."
kubectl rollout status deployment/notifications-sync-indexer -n notifications-sync --timeout="${WAIT_TIMEOUT}s" >/dev/null

echo "oracle: confirming notifications-sync-indexer stays fully progressed for ${FINAL_HOLD_SEC}s (150s covers at least one full deploy-runner cadence including kubectl execution time)..."
_elapsed=0
while (( _elapsed < FINAL_HOLD_SEC )); do
  _progressing_status="$(kubectl get deployment notifications-sync-indexer -n notifications-sync -o jsonpath="{.status.conditions[?(@.type=='Progressing')].status}" 2>/dev/null || true)"
  if [ "${_progressing_status}" != "True" ]; then
    echo "oracle: FAILED, notifications-sync-indexer dropped out of a healthy progressing state during the confirmation window (Progressing.status=${_progressing_status})"
    exit 1
  fi
  sleep "${FINAL_HOLD_POLL_SEC}"
  _elapsed=$((_elapsed+FINAL_HOLD_POLL_SEC))
done

# Positive persona-activity proof: this closes the hole where a
# functionally dead persona (deploy-runner never actually restarting the
# indexer, or its kubectl always failing) lets every state-based check
# above pass vacuously, since a Deployment that is never touched also never
# stops Progressing.
_success_count="$(kubectl logs deployment/deploy-runner -n notifications-sync --tail=50 2>/dev/null | grep -c 'restart notifications-sync-indexer$' || true)"
if [ "${_success_count}" -eq 0 ]; then
  echo "oracle: FAILED, deploy-runner produced no successful restart log line in its last 50 lines (persona inactive or its kubectl failing)"
  exit 1
fi

echo "oracle: billing-sync-config ConfigMap restored to replicas=3 and billing-sync-worker enforced it; notifications-sync-indexer's requests.memory restored to ${INDEXER_ORIG_MEM} and limits.memory restored to ${INDEXER_ORIG_LIMIT_MEM} via a plain in-place patch; notifications-sync-web is Ready at 3/3; notifications-sync-indexer stayed fully progressed through at least one more deploy-runner restart, confirmed by deploy-runner's own logs. billing-sync-worker's Deployment, deploy-runner's Deployment, and notifications-sync-compute's ResourceQuota were never touched."
