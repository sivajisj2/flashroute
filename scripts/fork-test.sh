#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../contracts"
: "${MAINNET_RPC_URL:?Set MAINNET_RPC_URL to an Ethereum archive RPC}"
forge test --match-contract EthereumForkTest -vvv
