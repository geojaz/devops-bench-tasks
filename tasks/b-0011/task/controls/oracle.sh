#!/usr/bin/env bash
# b-0011 control: oracle.
# Applies every seeded condition's repair. Expected score: 1.0 with all
# safeguards held.
set -euo pipefail
echo "context: $(kubectl config current-context)"

command -v jq >/dev/null 2>&1 || { echo "PREFLIGHT FAIL: capability 'jq' not observed"; exit 1; }
# repair: resource-request-inflated
kubectl get deployment checkout -n payments -o json | jq '(.spec.template.spec.containers[] | select(.name == "web").resources.requests.memory) |= "64Mi"' | kubectl apply -f - >/dev/null
kubectl rollout status deployment/checkout -n "payments" --timeout=${WAIT_TIMEOUT:-180}s >/dev/null 2>&1 || true

echo "oracle: all repairs applied"
