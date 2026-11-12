# Threat model and security assumptions

## Assets and actors

The receiver's balances, owner privileges, operator authority, signed transaction intent, API token, database ledger and deployment configuration are security assets. The browser, network requests, DEX responses and RPC responses are input boundaries. Owners select the lender, routers and supported assets; a malicious approved integration can violate assumptions.

| Threat | Implemented control | Residual limit |
|---|---|---|
| Anyone starts a loan | Dedicated operator gate | Compromised operator can submit allowed but bad plans |
| Forged/replayed callback | Immutable lender, initiator, active-plan hash, single-entry flag | Trusted lender assumption |
| Loss masked by donated balance | Start/final balance delta checks | Only standard non-rebasing ERC20 assets supported |
| Slippage / unprofitable settlement | Two minimum outputs, deadline and profit floor | A reverted transaction still consumes real gas on public networks |
| Approvals persist across swaps | Exact amounts, zero-first resets and repayment cleanup | Malicious tokens/routers remain out of scope |
| Administrative changes during loan | Idle-only administration and rescue | Owner remains highly privileged |
| Duplicate submissions | Atomic SQL claim and simulation-id idempotency | Different simulation IDs may represent equivalent trades |
| Crash or timeout after send | Ambiguous status; no automatic resend | Manual RPC/database reconciliation required |
| API abuse | Bearer token, Nginx 3 requests/sec + burst 15, 8 KiB body limit | Single operator token; no per-user RBAC or OIDC |
| Browser token leak | Memory-only token, no analytics or URL token | XSS, malicious extensions and compromised browser remain risks |
| Exposed local wallet | RPC not published by Compose, chain guard | Never add a public Anvil port mapping |
| Quote staleness | Same-block reads, short deadline, re-estimation | RPC trust; no canonical-finality or reorg tracking |

## Owner operations

Use a multisig owner and isolated operator for any separately reviewed deployment. Ownership uses proposal/acceptance. Owners can pause execution, revoke router/asset approval, rotate the operator and rescue idle balances. Those controls exist on the contract; no UI admin transaction signer is provided.

## Token compatibility

Demo tokens have six decimals. The receiver's raw balance accounting can support varying decimals, but the current backend/UI assumes six-decimal loan units and refuses non-local chains. Fee-on-transfer, rebasing, callback-bearing, blacklistable, pausable and nonstandard tokens need explicit testing. Do not infer support from the minimal ERC20 interface.

## Before live execution

A production release needs an independent audit, broader adversarial/invariant tests, per-network token/router verification, live gas conversion/oracle controls, RPC quorum/finality policies, external signing and nonce ownership, private relay strategy, managed identity, incident response, and operational monitoring. These are roadmap requirements, not completed features.
