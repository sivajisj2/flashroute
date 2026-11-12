#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
(cd contracts && forge fmt --check && forge test -vv)
cargo fmt --manifest-path backend/Cargo.toml --check
cargo clippy --manifest-path backend/Cargo.toml --locked --all-targets -- -D warnings
cargo test --manifest-path backend/Cargo.toml --locked
npm ci --prefix frontend
npm run test --prefix frontend
npm run build --prefix frontend
