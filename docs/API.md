# API reference

Base path: `/api/v1`. All endpoints require `Authorization: Bearer <OPERATOR_API_KEY>`. Tokens must have at least 24 characters. Errors use `{ "error": "message" }` for application errors. Axum extractor failures may use plain text; use correct JSON and UUID inputs. The UI uses same-origin requests; there is no wildcard CORS configuration.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Database and chain readiness, deployment addresses |
| GET | `/opportunities?amount=10000000000` | Quote both route directions, input in 6-decimal base units |
| POST | `/simulations` | Validate, simulate, estimate gas, persist ready plan |
| POST | `/simulations/{id}/execute` | Claim and submit existing plan to local Anvil |
| GET | `/executions` | Latest 100 plans with status, quote, transaction hash and timestamps |

Unauthenticated infrastructure endpoints: `GET /livez` returns `ok`; `GET /metrics` returns Prometheus text. They are reachable on the internal API container, not through the web's `/api/` proxy. `/livez` checks process availability; authenticated `/health` checks dependencies.

## Examples

Keep tokens out of shell history and logs. Read a private local `.env` value into the environment:

```bash
export OPERATOR_API_KEY="$(sed -n 's/^OPERATOR_API_KEY=//p' .env)"
curl -sS http://localhost:3000/api/v1/health \
  -H "Authorization: Bearer $OPERATOR_API_KEY"

curl -sS 'http://localhost:3000/api/v1/opportunities?amount=10000000000' \
  -H "Authorization: Bearer $OPERATOR_API_KEY"

curl -sS http://localhost:3000/api/v1/simulations \
  -H "Authorization: Bearer $OPERATOR_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"route":"a-b","amount":10000000000,"slippage_bps":10,"min_profit":5000000}'
```

Simulation response fields:

| Field | Meaning |
|---|---|
| `id` | UUID used to claim and retry the same execution |
| `status` | `ready` after a successful simulation |
| `gas` | `eth_estimateGas` result in gas units, not currency |
| `expires_at` | Unix timestamp; initially 90 seconds after creation |
| `opportunity` | Block-pinned quotes, premium, estimated net and policy reserve |
| `transaction` | Exact receiver calldata with sender and receiver addresses |

Use the returned UUID, not a newly generated one, for execution:

```bash
SIMULATION_ID=REPLACE_WITH_RETURNED_UUID
curl -sS "http://localhost:3000/api/v1/simulations/$SIMULATION_ID/execute" \
  -H "Authorization: Bearer $OPERATOR_API_KEY" \
  -H "Idempotency-Key: $SIMULATION_ID" \
  -H 'Content-Type: application/json' -d '{}'
```

A duplicate request returns the existing state and `replayed: true`. An expired ready plan is not submitted; the background loop labels it expired. Re-simulate to create a fresh plan. Never create a new plan merely to retry an `unknown` submission until you reconcile the chain.

## Validation and statuses

- Amount: 100–100,000 dUSDC inclusive, expressed as integer base units.
- Route: `a-b` or `b-a`.
- Slippage: 0–100 basis points inclusive.
- Minimum profit: 1–1,000,000,000 base units, excluding the additional $20 demo gas reserve.
- Header `Idempotency-Key`: must equal the simulation UUID exactly.
- Backend chain: must be 31337, with explicit `ALLOW_LOCAL_EXECUTION=true` for sends.

HTTP 401: missing/wrong operator token. 403: submission disabled/wrong chain. 404: missing simulation. 422: invalid business input or unprofitable/reverted simulation. 429: concurrent scan/rate limit. 502: database/RPC operation failed or submission outcome is ambiguous.

One operator token is the initial access model; OIDC, user roles, audit actor identities and token rotation UI are not implemented.
