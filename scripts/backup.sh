#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p backups
docker compose exec -T db pg_dump -U flashroute flashroute | gzip > "backups/flashroute-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
echo 'Database backup saved under backups/; copy it to encrypted off-host storage.'
