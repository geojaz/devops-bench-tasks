#!/usr/bin/env bash
# b-0059 control: do_nothing.
# Applies no changes to the seeded state. Expected score: c=0/3
# (workload-restored never passes since billing-sync-config's ConfigMap is
# never touched, fix-persists holds on an already-unhealthy workload so it
# never even starts passing, and consumer-path-restored never passes since
# allow-from-search-api's corrupted namespaceSelector is never touched
# either), with every safeguard held, so score == c == 0.0.
set -euo pipefail
echo "do_nothing: no changes applied"
