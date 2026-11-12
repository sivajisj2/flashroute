#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z ${OPERATOR_API_KEY:-} && -f .env ]]; then
  OPERATOR_API_KEY=$(sed -n 's/^OPERATOR_API_KEY=//p' .env)
  export OPERATOR_API_KEY
fi
python3 scripts/smoke.py
