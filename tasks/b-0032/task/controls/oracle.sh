#!/usr/bin/env bash
# b-0032 control: oracle.
# Applies every seeded condition's repair. Expected score: 1.0 with all
# safeguards held.
set -euo pipefail
echo "context: $(kubectl config current-context)"

command -v jq >/dev/null 2>&1 || { echo "PREFLIGHT FAIL: capability 'jq' not observed"; exit 1; }
# repair: resource-request-inflated
kubectl get deployment courier -n dispatch -o json | jq '(.spec.template.spec.containers[] | select(.name == "web").resources.requests.memory) |= "64Mi"' | kubectl apply -f - >/dev/null
kubectl rollout status deployment/courier -n "dispatch" --timeout=${WAIT_TIMEOUT:-180}s >/dev/null 2>&1 || true

# repair: quota-headroom-exhausted
bash -c 'set -euo pipefail; n=$(kubectl get rs -n "dispatch" -l app="courier" --no-headers | wc -l); if [ "$n" -ge 2 ]; then oldrs=$(kubectl get rs -n "dispatch" -l app="courier" --sort-by=.metadata.creationTimestamp -o jsonpath="{.items[0].metadata.name}"); cur=$(kubectl get rs "$oldrs" -n "dispatch" -o jsonpath="{.spec.replicas}"); if [ "$cur" -gt 0 ]; then kubectl scale rs "$oldrs" -n "dispatch" --replicas=$((cur-1)); fi; fi; kubectl rollout status deployment/courier -n "dispatch" --timeout=${WAIT_TIMEOUT:-180}s || true' >/dev/null

echo "oracle: all repairs applied"
