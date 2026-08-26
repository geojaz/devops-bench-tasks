#!/usr/bin/env bash
# b-0022b control: oracle.
# Applies every seeded condition's repair. Expected score: 1.0 with all
# safeguards held.
set -euo pipefail
echo "context: $(kubectl config current-context)"

command -v jq >/dev/null 2>&1 || { echo "PREFLIGHT FAIL: capability 'jq' not observed"; exit 1; }
# repair: workload-replicas-set
kubectl patch deployment shelfview -n storefront --type=merge -p '{"spec": {"replicas": 3}}' >/dev/null
kubectl rollout status deployment/shelfview -n "storefront" --timeout=${WAIT_TIMEOUT:-180}s >/dev/null 2>&1 || true

# repair: cronjob-suspend-set
kubectl patch cronjob price-refresh -n storefront --type=merge -p '{"spec": {"suspend": false}}' >/dev/null

# repair: readiness-probe-port-set
kubectl get deployment search-api -n storefront -o json | jq '(.spec.template.spec.containers[] | select(.name == "web").readinessProbe.httpGet.port) |= 8085' | kubectl apply -f - >/dev/null
kubectl rollout status deployment/search-api -n "storefront" --timeout=${WAIT_TIMEOUT:-180}s >/dev/null 2>&1 || true

echo "oracle: all repairs applied"
