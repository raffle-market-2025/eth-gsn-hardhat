# Raffle marketplace and GSN

Solidity raffle marketplace, ticket NFTs, Chainlink VRF v2.5/Automation and
OpenGSN sponsored promo admission.

Use Node >=22.10 and npm >=10. Install dependencies without executing install
scripts, run local security regression tests, then compile Hardhat artifacts:

```
npm ci --ignore-scripts
npm test
npm run compile
```

The tests use an isolated EVM without RPC credentials or network forks. They
compile all production contracts, verify deployment size and exercise the
critical/high audit scenarios using full contract instances and local mocks.

Read [SECURITY.md](SECURITY.md) before deployment. The remediation changes the promo
constructor, admission API and refund flow. Existing deployments require a
migration; leaked credentials require manual rotation. Use `.env.example` for
variable names, export fresh credentials or configure Hardhat's keystore, and
copy the relay config example to the ignored local config path.

Promo admission requires a server-issued EIP-712 signature. A funded VRF
subscription and a keeper finalizing received randomness are also required.
See [SECURITY.md](SECURITY.md) for the exact typed-data schema and lifecycle.
