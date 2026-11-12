#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/setup.sh
if ! rg -q '^DOMAIN=[a-zA-Z0-9]' .env 2>/dev/null; then
  if ! grep -Eq '^DOMAIN=[a-zA-Z0-9]' .env; then echo 'Set DOMAIN in .env to your DNS hostname before deployment.' >&2; exit 1; fi
fi
docker compose -f compose.yaml -f compose.vps.yaml up -d --build --wait --wait-timeout 300
echo 'VPS services started; Caddy will obtain HTTPS for DOMAIN. Verify with scripts/smoke.sh using BASE_URL.'
