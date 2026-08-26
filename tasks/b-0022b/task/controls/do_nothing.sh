#!/usr/bin/env bash
# b-0022b control: do_nothing.
# Applies no changes to the seeded state. Expected score: c=0 against
# task.yaml's verification_spec (objectives are not met; nothing was touched).
set -euo pipefail
echo "do_nothing: no changes applied"
