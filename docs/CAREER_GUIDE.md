# Explain and extend FlashRoute in interviews

## Relevant roles

| Role | Evidence in this repository | Topics to demonstrate |
|---|---|---|
| Solidity / DeFi engineer | FlashExecutor, Aave callback, V2 swap boundaries, Foundry tests | Atomicity, premium math, allowances, balance deltas, reentrancy boundaries |
| Rust backend engineer | Axum service, Tokio receipt worker, SQLx ledger, Alloy ABI | Async I/O, typed encoding, validation, transactions and retry semantics |
| Web3 full-stack engineer | React console, API, persisted simulations, real local receipts | State consistency, integer units, useful error states and operator UX |
| Blockchain infrastructure engineer | Docker topology, readiness, CI, metrics, VPS ingress | Trust boundaries, deployment lifecycle, recovery and observability |

## Five-minute demo

1. Run `./scripts/up.sh` and connect using the generated token.
2. Explain why the two seeded markets begin with a price discrepancy.
3. Scan both directions and explain premium and policy gas reserve.
4. Simulate the winning route. Inspect the ABI calldata, gas units and 90-second expiration.
5. Execute once; show receipt confirmation in the ledger.
6. Show the contract's start-balance invariant and Foundry rollback test.
7. Run `scripts/smoke.sh` to demonstrate concurrent duplicate protection.
8. Explain which production features remain out of scope.

## Technical questions to prepare

1. Why does a flash loan revert instead of leaving a debt here? The lender is repaid within the same EVM transaction and rejects failed repayment; atomic rollback restores prior state.
2. Why check the asset balance before borrowing? Existing donations must not disguise a losing strategy.
3. Why check the balance again after the callback? The lender has only pulled repayment after callback return; the final check verifies the post-repayment condition.
4. Why require the initiator to be the executor itself? A third party could otherwise request loans to the receiver with chosen callback data.
5. Why use an active plan hash as well? It binds the callback to the operation authorized by the operator and prevents unsolicited or repeated callbacks.
6. Why pin quotes to a block? Two quotes from different states can create a false spread. Pinned reads still depend on RPC honesty and retained historical state.
7. Why not store amounts as floating point? Token precision and rounding affect debt/profit boundaries. Keep ABI/backend units as integers.
8. Is the SQL claim exactly-once delivery? No. It ensures at-most-once submission per plan, with an unavoidable external-RPC/database dual-write ambiguity.
9. What happens if a process crashes after sending but before storing the hash? The row becomes unknown and needs manual nonce/chain reconciliation; blind retry can duplicate a trade.
10. Does `eth_call` guarantee success later? No. Pool state, gas environment and inclusion order can change. On-chain checks protect limits, while a failed public transaction can still cost gas.
11. Are displayed profits actual returns? No. They are quote estimates minus premium and a fixed demo reserve. The UI does not label them realized P&L.
12. Why separate owner and operator? Governance and recovery authority can be isolated from routine strategy execution.
13. Why aren't public mainnet transactions enabled? Production needs audited integrations, nonce management, external signing, live cost controls and MEV strategy.
14. Why not use a queue in the first version? PostgreSQL's conditional update supplies the required single-plan claim. An additional queue adds retry/delivery complexity without removing RPC ambiguity.
15. How would you scale it? Separate quote workers from API traffic, use bounded concurrency and cached block snapshots, partition opportunities, add signer nonce ownership, and introduce durable outbox/reconciliation designs.

## Honest resume wording after you run and understand it

- Built a flash-loan arbitrage sandbox using Solidity/Foundry, Rust/Axum, React and PostgreSQL, integrating on-chain route quotes, preflight simulation and local receipt reconciliation.
- Implemented operator authorization, callback-plan binding, profit-floor checks and donation-resistant balance accounting; validated rollback behavior and fuzzed profitable input ranges.
- Added atomic database submission claims, idempotent plan execution, Docker workflows, CI checks, metrics and documented VPS deployment.

Do not claim production trading volume, financial gains, an independent audit, institutional usage or years of professional DeFi experience from this project. Run it, inspect the code, change something meaningful, and explain its tradeoffs before adding it to a resume.

## Prioritized next increments

1. External signer abstraction with exclusive nonce ownership and a durable submission outbox.
2. Archive-RPC fork CI and deeper malicious-lender/router/token tests plus invariant handlers.
3. Mainnet quote adapters with per-token decimals, reliable gas conversion and RPC quorum.
4. OIDC/RBAC and identified audit actors; managed secrets and off-host observability.
5. Private relay support, reorg-aware finality, live incident drills and independent review.
