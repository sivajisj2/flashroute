# Operations runbook

## Dependency readiness

Use `docker compose ps`, then `docker compose logs --tail=100 api deploy db anvil web`. `/livez` establishes that the API process is running; authenticated `/api/v1/health` verifies PostgreSQL and chain reachability. If deployment never completes, read the deploy service log before restarting other services.

## No profitable routes

This can be a valid state. AMM reserves change after executions and repeated arbitrage closes the seeded spread. Increase/decrease loan size within the allowed range and rescan. Do not interpret a negative estimate as a system failure. Reset the local stack only when you intentionally want a new fixture, preserving/archiving any evidence first.

## Reverted simulations

Check amount, premium, both min outputs, short deadline, allowed router/token configuration and profitability. The UI profit floor includes an additional $20 policy reserve. A passing quote is not a promise that a later simulation or mined transaction will succeed.

## Unknown/submitting outcomes

The RPC call and SQL update are separate systems. A node may accept a transaction before the client times out or the process crashes. Rows left submitting become unknown after two minutes. Never automatically re-send. Inspect the sender nonce, recipient/calldata, recent blocks and transaction receipts. Match execution events and on-chain state before deciding whether a trade did or did not occur. This release provides inspectable ledger records but no automated ambiguous-send recovery command.

## Pending receipt

Check chain reachability and the transaction hash. The receipt worker polls every two seconds. `confirmed` means an Anvil receipt with status 1 was observed, not multi-block economic finality. A public-chain release needs confirmation depth and reorg-aware reconciliation.

## Token rotation

Update the private `.env` with a new random token at least 24 characters long; recreate the API container so it reads the new value. Reconnect the browser. Tokens are never embedded into the frontend build. Keep `.env` mode 600.

## Lost chain or database state

Treat the PostgreSQL ledger, Anvil state volume, and deployment artifact as one environment. Restore a consistent snapshot or intentionally create a new environment and archive the old records. Reused deterministic contract addresses do not prove continuity of chain history.

## Incident containment

Stop API ingress and API workers if the operator token is exposed. On a separately deployed receiver, an authorized owner can call `setPaused(true)` and revoke router/asset allowlists. Rotate the operator through owner governance. Preserve database records and chain logs before recovery.
