#!/usr/bin/env bash
# b-0053 control: oracle.
# Applies every seeded condition's repair. Expected score: 1.0 with all
# safeguards held.
set -euo pipefail
echo "context: $(kubectl config current-context)"

# repair: gke-node-pool-max-nodes-set
gcloud container node-pools update "primary-node-pool" --cluster="${CLUSTER_NAME}" --location="us-east1-d" --project="${GCP_PROJECT_ID:-${PROJECT_ID:?}}" --enable-autoscaling --min-nodes="1" --max-nodes="2" --quiet >/dev/null

echo "oracle: all repairs applied"
