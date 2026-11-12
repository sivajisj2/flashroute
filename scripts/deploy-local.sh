#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../contracts" 2>/dev/null || cd /contracts
RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
export RPC_URL
[ "$(cast chain-id --rpc-url "$RPC_URL")" = '31337' ] || { echo 'Local chain 31337 required' >&2; exit 1; }
mkdir -p deployments
if [ -s deployments/local.json ]; then
  executor=$(sed -n 's/.*"executor": *"\([^"]*\)".*/\1/p' deployments/local.json)
  if [ -n "$executor" ] && [ "$(cast code "$executor" --rpc-url "$RPC_URL")" != '0x' ]; then
    echo 'Existing local deployment is present; skipping deployment.'
    exit 0
  fi
fi
forge script script/DeployLocal.s.sol:DeployLocal --rpc-url "$RPC_URL" --broadcast --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
chmod 644 deployments/local.json
