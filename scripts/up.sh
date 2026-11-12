#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/setup.sh
docker compose version >/dev/null
docker compose up -d --build --wait --wait-timeout 300
echo 'FlashRoute is ready: http://localhost:3000'
echo 'Operator token: OPERATOR_API_KEY in .env (not printed in logs).'
