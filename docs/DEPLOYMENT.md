# Run and deploy

## Local Docker deployment

Requirements: Docker Engine with Compose v2, Bash and OpenSSL. On Linux, allow the current user to use Docker through your normal system administration setup.

```bash
git clone https://github.com/sivajisj2/flashroute.git
cd flashroute
./scripts/up.sh
```

Open http://localhost:3000. Read `OPERATOR_API_KEY` in your private `.env` and enter it in **Connect operator**. It remains in browser memory only. Scan, simulate the profitable direction, review, and execute. The execution ledger will update after receipt polling.

`up.sh` creates random secrets only when `.env` does not exist, builds the API/UI, starts PostgreSQL/Anvil, deploys/seeds the demo contracts, and waits for service health. It does not publish RPC or PostgreSQL host ports. Cold builds need several minutes and Internet access for Rust crates, npm packages, container images and Solidity compiler downloads.

```bash
./scripts/smoke.sh                  # exercises local demo execution
make logs                          # follow service logs
./scripts/down.sh                  # stop; preserve named volumes
./scripts/backup.sh                 # private PostgreSQL backup

docker compose --profile observability up -d prometheus
# Prometheus: http://localhost:9090
```

The Prometheus profile is optional. It scrapes the private API `/metrics` endpoint. Anvil state, deployment addresses and PostgreSQL state live in separate named volumes. Keep those volumes together when restoring/migrating. Anvil writes state periodically and on orderly shutdown. The deployment initializer skips when its recorded executor has code.

## Linux VPS with automatic HTTPS

The app remains a demo sandbox when hosted. Requirements: a Linux VPS (4 GB RAM recommended, sufficient free disk for compiler builds), Docker/Compose, a domain under your control, and ports 80/443 reachable. Point DNS A/AAAA records to the server. Do not create an AAAA record unless IPv6 works.

On the server:

```bash
git clone https://github.com/sivajisj2/flashroute.git
cd flashroute
./scripts/setup.sh
# Edit .env: set DOMAIN=flashroute.your-domain.example
./scripts/deploy-vps.sh
```

Caddy obtains and renews a TLS certificate, then proxies to the internal web container. Only Caddy is publicly bound; the web container also retains a loopback-only port for diagnosis. No server credentials or domain were supplied with the project, so this repository provides the deploy workflow without claiming an existing live VPS deployment.

For a quick private demo, use SSH port forwarding instead of configuring a public domain:

```bash
ssh -L 3000:127.0.0.1:3000 your-vps
```

Then open localhost:3000 locally. Keep the operator token private.

## Upgrades, backups and recovery

1. Back up PostgreSQL with `scripts/backup.sh`; copy backups to private encrypted off-host storage.
2. Record the current Git commit and preserve `.env`, all named volumes and the deployment JSON.
3. Review changes, especially schema/accounting changes. The current schema bootstrap is additive/idempotent, not a versioned migration engine.
4. Pull the reviewed commit and rerun `deploy-vps.sh` (or `up.sh` locally).
5. Run the smoke check and inspect logs. Smoke creates a real local demo execution.
6. Roll back source to the recorded commit and rebuild if needed. Database schema changes need their own compatible restore/migration plan.

Do not remove named volumes during routine shutdown. If chain state is intentionally reset, also clear/recreate the execution ledger and deployment artifact as one planned reset. Old transaction hashes belong to the old chain even when contract addresses repeat.

## Native development

Install Foundry 1.4.4, Rust 1.99.1 (rustup reads `rust-toolchain.toml`), Node 22 and PostgreSQL 17+. Use PostgreSQL credentials/database you control.

Terminal 1:

```bash
anvil --chain-id 31337
```

Terminal 2:

```bash
./scripts/deploy-local.sh
export DATABASE_URL=postgres://YOUR_USER:YOUR_PASSWORD@localhost:5432/flashroute
export OPERATOR_API_KEY=YOUR_RANDOM_TOKEN_AT_LEAST_24_CHARACTERS
export ALLOW_LOCAL_EXECUTION=true
cargo run --manifest-path backend/Cargo.toml
```

Terminal 3:

```bash
npm ci --prefix frontend
npm run dev --prefix frontend
```

Vite proxies `/api` to `127.0.0.1:8080`. `RPC_URL`, `DEPLOYMENT_FILE` and `BIND_ADDR` override defaults when needed. Docker's Nginx rate limits/security headers do not apply to the Vite development server.

## Ethereum fork validation

The optional test pins Ethereum block 21,000,000. It reads a real Aave premium, obtains a real V2 quote and checks atomic rollback of an intentionally unprofitable two-swap loan. Use an archive-capable RPC:

```bash
export MAINNET_RPC_URL=https://YOUR_ARCHIVE_PROVIDER
./scripts/fork-test.sh
```

Without that variable, the fork test is explicitly skipped. The receiver deployment script `contracts/script/DeployExecutor.s.sol` accepts `AAVE_POOL`, `OWNER`, `OPERATOR`. Run a dry simulation with Foundry first and use your own encrypted keystore/hardware signing workflow if independently deploying. The application backend deliberately refuses production chains; deployment of a receiver alone does not enable live trading.
