#!/usr/bin/env bash
# b-0061 control: do_nothing.
# Unchanged from b-0059's do_nothing.sh (b-0061 is a SUBSTRATE-ABLATION
# control twin: identical faults and grading, minimal world).
# Applies no changes to the seeded state. Expected score: c=0/3
# (workload-restored never passes since billing-sync-config's ConfigMap is
# never touched, fix-persists holds on an already-unhealthy workload so it
# never even starts passing, and consumer-path-restored never passes since
# allow-from-search-api's corrupted namespaceSelector is never touched
# either), with every safeguard held, so score == c == 0.0.
set -euo pipefail
echo "do_nothing: no changes applied"
