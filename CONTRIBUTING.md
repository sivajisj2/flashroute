# Contributing

1. Fork the repository and create a focused branch.
2. Use Foundry 1.4.4, Rust 1.99.1, Node 22 and Docker Compose v2.
3. Run `./scripts/check.sh` and `./scripts/up.sh && ./scripts/smoke.sh`.
4. Explain the behavioral change, test evidence, and any risk to contract accounting.
5. Keep generated secrets, broadcast caches, database backups and local deployment addresses out of commits.

Changes affecting callback authorization, balance deltas, approvals, or submission retries require adversarial regression coverage. Do not introduce live execution without a separate design review and signer threat model.
