#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f .env ]]; then echo '.env already exists; preserving secrets.'; exit 0; fi
command -v openssl >/dev/null || { echo 'Install openssl first.' >&2; exit 1; }
umask 077
printf 'POSTGRES_PASSWORD=%s\nOPERATOR_API_KEY=%s\nDOMAIN=\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 32)" > .env
echo 'Created .env. Use its OPERATOR_API_KEY to connect the console.'
