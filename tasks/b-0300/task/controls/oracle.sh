#!/usr/bin/env bash
# b-0300 control: oracle.
# Applies every seeded condition's repair. Expected score: 1.0 with all
# safeguards held.
set -euo pipefail
echo "context: $(kubectl config current-context)"

# repair: gke-node-pool-max-nodes-set
gcloud container node-pools update "${CLUSTER_NAME}" --cluster="${HOST_CLUSTER_NAME}" --location="${HOST_CLUSTER_LOCATION}" --project="${GCP_PROJECT_ID:?}" --enable-autoscaling --min-nodes="1" --max-nodes="2" --quiet >/dev/null

echo "oracle: all repairs applied"
