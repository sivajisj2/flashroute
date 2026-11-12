# Validation evidence

Date: 12 November 2026. This report distinguishes completed native checks from infrastructure and external-network checks.

| Check | Result | Evidence / limitation |
|---|---|---|
| Solidity compile + Foundry tests | PASS | Solidity 0.8.30; 13 tests passed, including 256 fuzz cases |
| Ethereum historical fork test | PASS | Public archive endpoint, block 21,000,000; real Aave + Uniswap; precise profit-floor revert and restored reserves |
| Rust unit tests | PASS | 4 tests cover cost math, loss accounting, rounding and bounds |
| Strict Rust Clippy | PASS | `--locked --all-targets -- -D warnings` |
| Rust formatting | PASS | `cargo fmt` applied; checked before delivery |
| Frontend unit tests | PASS | 2 tests cover exact base-unit conversion and invalid amounts |
| TypeScript + Vite production build | PASS | React/TypeScript console builds successfully |
| Native E2E services | PASS | PostgreSQL 18.6, Anvil 1.4.4, Rust API; full smoke workflow |
| Concurrent submit protection | PASS | Two parallel requests produced one submission and one replay |
| Receipt reconciliation | PASS | Demo execution reached confirmed status |
| Browser interaction/screenshots | PASS | Operator connection, quote display, simulation review, manual local submit, confirmed ledger, registry; four JPEG screenshots |
| Docker daemon execution | NOT RUN locally | This build environment has no Docker daemon; CI includes Compose E2E |
| VPS HTTPS deployment | NOT RUN | Requires user's VPS/domain; runnable scripts and Caddy config included |

## Captured native smoke result

```json
{
  "result": "PASS",
  "chain_id": 31337,
  "simulation": "f3bcf0ed-e680-48b5-9083-c76e0b0a9c6d",
  "tx_hash": "0x8883fd28701412ef609d3a83433c7a89698edc9a8d17503a4e3e673eda07630b",
  "status": "confirmed",
  "gas_estimate": 364003,
  "checks": [
    "auth", "input bounds", "losing route rejection", "simulation",
    "atomic concurrent claim", "receipt confirmation", "idempotent replay"
  ]
}
```

This hash identifies a transaction in an ephemeral local test chain; it is not a mainnet transaction or a financial performance claim. Tests consume and change local AMM reserves. Repeated smoke runs can eventually close the seeded arbitrage opportunity.

## Reproduce

```bash
./scripts/check.sh
./scripts/up.sh
./scripts/smoke.sh
```

The fork test was additionally run with `MAINNET_RPC_URL=https://ethereum.reth.rs/rpc`. The default offline run still skips it when no RPC is configured.

Native service checks used PostgreSQL 18.6 supplied by a temporary development runner. Compose pins PostgreSQL 17; its own integration workflow must validate the container stack. Neither a successful native smoke nor a successful UI build substitutes for that container-level check.
