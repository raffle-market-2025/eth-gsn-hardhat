# Security fixes and migration

This change addresses C-01 and H-01 through H-06 from the audit of commit
`57b8d25a530b81c61ba307949c58d0bf30fbc012`. It changes deployed interfaces and requires
new deployments. Existing immutable marketplace infrastructure and its existing
clones do not receive these fixes automatically. Do not reuse published keys.

## Credentials (C-01: operational remediation still required)

Tracked `.env`, `mnemonic.txt`, RPC/API credentials and the local relay config have
been removed from the current source. They remain compromised in Git history and
in any existing copies. No wallet rotation, asset transfer, API revocation or
history rewrite is performed by these code changes. Before funding new deployments:

1. Create fresh wallets outside the repository; move funds and rotate privileged
   contract addresses, API keys, the relayer and admission signer as applicable.
2. Revoke old approvals and permissions; inspect activity on compromised accounts.
3. Coordinate any repository-history cleanup separately. Removing history does
   not restore the secrecy of old credentials.

Use `.env.example` as a list of variable names, and export them in your shell or
use Hardhat's keystore. Hardhat configuration intentionally does not load `.env`
automatically. Copy `config/gsn-relay-config.example.json` to the ignored local
config path and supply a new endpoint. Never commit a seed phrase or private key.
The relay owner address in the example is illustrative: replace it with a new
address whose key has never been published.

## VRF finalization (H-01)

The charged coordinator callback stores the word once, with a separate received
flag so a valid zero word is supported. It makes no per-raffle calls. Requests
keep their original raffle addresses. `finalizeRaffle(requestId, raffleId)` is
permissionless and retryable using only that stored randomness. The existing
Automation keeper also finds and finalizes fulfilled requests. Failure leaves
`inFlight` and the original word intact; no new randomness is requested.
`clearInFlight` was removed to prevent bypassing pending requests.
Marketplace/config changes are blocked while raffles are pending.

## Refunds (H-02)

Either the host or the marketplace owner may cancel an OPEN raffle. Anyone may
cancel after the deadline if the threshold or the minimum winner count was not
met. Eligible draws cannot be cancelled by unrelated callers. No cancellation is
allowed after CALCULATING. Cancelled ticket owners call `claimRefund(tokenId)`;
it checks current ownership, marks the claim, burns the ticket and returns its
recorded purchase price. A rejected payment rolls back only that claim. Cleanup
cannot burn refund claims, and the owner cannot sweep cancelled/open balances.
The frontend must expose the per-ticket claim action.

## LINK and scanning (H-03/H-04)

Generic registration is internal. The two public registration wrappers remain
owner-only. Both keepers recompute a bounded scan on execution, rather than
trusting caller-provided batch IDs or cursors. A partially scanned registry
returns upkeep-needed even with no matching raffle, so the next window is reached.
This entails cursor-only upkeep costs when registry size exceeds MAX_SCAN; tune
limits and funding accordingly. An entirely scanned idle registry does not
request work. Actual batch size remains bounded by MAX_BATCH.

## Signed promo admission (H-05)

`enterRaffle(bytes32 ipHash, bytes2 country2, uint256 deadline, bytes signature)`
requires an EIP-712 signature from the configured admission service. Domain:

- name: `PromoRaffle`
- version: `1`
- chainId: target network chain ID
- verifyingContract: the new promo contract address

The `Entry` type, in this exact order, is:

```
Entry(address participant,bytes32 ipHash,bytes2 country2,uint256 cycle,uint256 deadline)
```

The service must determine the request IP itself, normalize/hash it consistently,
apply eligibility/rate limits, and sign for the authenticated wallet and current
cycle with a short expiration. Do not sign arbitrary IP hashes submitted by the
client. Country is signed as two bytes. The contract tracks both wallets and IPs
by cycle, independently of NFT ownership, and supports ERC-2771 sender recovery.
Signatures are bound to the wallet, IP, country, cycle, deadline, chain and contract.
This repository does not contain an admission HTTP service: deploy/integrate one
before enabling public entry. Multiple identities/proxies require policy at that
service; on-chain signatures alone do not prove a unique person.

Both paymasters use the new selector. The default Paymaster sponsors only signed
entry, disallows value, and rejects recipient reverts; the whitelist paymaster
also verifies its trusted forwarder and rejects recipient reverts. No stale
unsigned two-argument entry function remains.

## Asynchronous promo draw (H-06)

The constructor now takes `(playersNeeded, trustedForwarder, deployer, Config)`.
Config contains `coordinator`, `subscriptionId`, `keyHash`, `callbackGasLimit`,
`entrySigner`. Counts are restricted to 1..200 to bound cleanup. Register the
new promo address as a consumer of a funded native-payment VRF v2.5 subscription.
The deploy script expects the deployer to own the supplied subscription.

The last entry requests randomness and freezes the cycle. Admitted wallets are
snapshotted at entry, so transferring NFTs after admission cannot change prize
eligibility. Ownership cannot change the player count during an active cycle.
The VRF callback only persists the word. Register the promo's
`checkUpkeep`/`performUpkeep` with an Automation keeper, or call
`finalizeCycle()` permissionlessly after fulfillment. Finalization allocates the
request-time unreserved prize balance, burns tickets and opens the next cycle.
It never sends ETH to the winner. The winner calls `claimPrize()` separately;
unclaimed prizes remain reserved from subsequent cycles. Ownership uses
Chainlink's two-step `transferOwnership`/`acceptOwnership`.

Update frontends, relayer ABIs and subscriptions before enabling the new contracts.
The supplied GSN smoke script consumes a service-generated signature, IP hash and
deadline; it does not mint its own eligibility attestations. The subgraph's input
function ABI must be regenerated from the new artifacts if function indexing is
used; the `RaffleEnter` event retains its five-field shape.

## Verification

Use Node >=22.10 and npm >=10:

```
npm ci --ignore-scripts
npm test
npm run compile
```

The security suite uses pinned solc 0.8.28, optimizer 200, viaIR, Shanghai and a
local Ganache EVM. It compiles all production contracts and asserts the EIP-170
bytecode limit, then tests full VRF callbacks, retries, refunds, registration,
scanning, signed admission, transfers, GSN sender handling and asynchronous
promo payouts. No external RPC or real credential is used. `.npmrc` accommodates
legacy ethers v5 peer requirements in Chainlink/GSN tooling; application code
uses ethers v6. `--ignore-scripts` avoids executing dependency install scripts.

The old Counter test referenced a missing contract and was replaced. This is a
regression suite for the scoped fixes, not proof of absence of vulnerabilities.
Other medium-severity audit items, including repeated marketplace prize payouts,
remain outside this change unless explicitly covered in the final change summary.
