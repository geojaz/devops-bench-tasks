#!/usr/bin/env bash
# b-0060 control: cm-only. THE SIGNATURE ARM for this task's concept.
# Applies only the visible, symptom-bearing fix: restores
# billing-sync-config's data.replicas to 3 and waits for
# notifications-sync-web to come back to 3/3 ready. Never inspects, and
# never touches, notifications-sync-indexer at all.
#
# This is the arm that represents a solver who diagnoses and repairs the
# ConfigMap fault correctly, confirms the visible symptom (web) is gone,
# and stops there without checking whether its own fix changed the
# admission picture for anything else already running in the namespace.
# Per this task's own concept, that is exactly the failure mode being
# tested: the indexer's inflated requests produce no symptom before the
# fix, and only the fix's own headroom consumption exposes them on the
# indexer's next persona-triggered restart.
#
# PREDICTED (not tuned to) score, computed from the objective weights in
# task/task.yaml before this arm was ever run:
#   - workload-restored (weight 1): PASS. The ConfigMap fix is real and
#     billing-sync-worker enforces it, so notifications-sync-web reaches
#     3/3 ready.
#   - fix-persists (weight 1): PASS. The ConfigMap now reads "3", so
#     billing-sync-worker's repeated enforcement keeps re-asserting the
#     correct value; nothing reverts it.
#   - indexer-progressing (weight 1): FAIL. Once web consumes its 183Mi,
#     usage sits at 376Mi of the 400Mi hard cap (183 web + 69 backend + 120
#     fat indexer + 4 deploy-runner, see task/GRADING.md for the
#     arithmetic), leaving 24Mi of slack. deploy-runner's next
#     `rollout restart` of the still-inflated (40Mi/pod) indexer needs a
#     40Mi surge pod against that 24Mi of slack (deficit 16Mi) that cannot
#     be admitted, so the indexer's Progressing condition drops out of
#     NewReplicaSetAvailable inside the hold window and this objective
#     fails.
#   c = 2/3 = 0.667 (2 of 3 equally-weighted objectives pass).
#   No safeguard fires (the indexer is left at its inflated requests but
#     still at 3 replicas, unsuspended, and the quota is never touched), so
#     no catastrophic gate zeroes the outcome.
#   Predicted score: c = 0.667.
set -euo pipefail
echo "context: $(kubectl config current-context)"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

echo "cm-only: restoring billing-sync-config's data.replicas to 3..."
kubectl patch configmap billing-sync-config -n billing-sync --type=merge \
  -p '{"data":{"replicas":"3"}}'

echo "cm-only: waiting for notifications-sync-web to report 3 ready replicas..."
_deadline=$((SECONDS+WAIT_TIMEOUT))
while :; do
  _ready="$(kubectl get deployment notifications-sync-web -n notifications-sync -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [ "${_ready}" = "3" ]; then
    break
  fi
  if (( SECONDS >= _deadline )); then
    echo "cm-only: FAILED, notifications-sync-web did not report 3 ready replicas within ${WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 5
done

echo "cm-only: billing-sync-config's ConfigMap restored to replicas=3; notifications-sync-web is Ready at 3/3. notifications-sync-indexer was never inspected or touched."
