# Tokenized Fund PoC — BNP Paribas Euro Money Market on Ethereum

Proof-of-concept tokenizing shares of the [BNP Paribas Euro Money Market fund](https://www.bnpparibas-am.com/en-be/fundsheet/marche-monetaire/bnp-paribas-funds-euro-money-market-classic-d-lu0083137926/) (ISIN: LU0083138064) on public Ethereum with permissioned transfers and a Chainlink-compatible NAV oracle.

## Context

In February 2026, BNP Paribas Asset Management [issued tokenized shares](https://group.bnpparibas/en/press-release/bnp-paribas-explores-public-blockchain-infrastructure-for-money-market-fund-tokenisation) of a French money market fund on public Ethereum via their AssetFoundry platform. This PoC demonstrates how such a tokenization could work technically, including the NAV feed problem — how does the daily Net Asset Value reach the blockchain in a verifiable, auditable way?

## Architecture

```
NAVOracle (Chainlink AggregatorV3Interface, 8 decimals)
├── PUBLISHER_ROLE can push daily NAV
├── deviation check (max 1% per update)
├── minimum update interval (12h default)
├── full round history (capped at 1000)
├── emergencyPublishNAV(nav, reason) — admin override with on-chain audit trail
└── consumed by PermissionedFundToken

WhitelistManager
├── COMPLIANCE_ROLE
├── addInvestor() / removeInvestor()
└── addInvestorsBatch()

PermissionedFundToken (tMMF-EUR)
├── reads NAV from oracle on every subscribe/redeem (staleness-checked)
├── subscribe() → mint to whitelisted investor at fresh oracle NAV
├── redeem() → burn shares at fresh oracle NAV
├── shareValueInCurrency() → portfolio valuation, scaled by oracle decimals
├── pause() / unpause() → regulatory freeze (halts BOTH primary and secondary)
├── forceRedeem() → admin-only, bypasses pause/staleness for KYC revocation
└── _update() → enforces whitelist + pause on every transfer
```

## Fund Reference Data

| Field | Value |
|-------|-------|
| Fund | BNP Paribas Funds Euro Money Market |
| ISIN | LU0083138064 |
| Symbol | tMMF-EUR |
| Currency | EUR |
| Domicile | Luxembourg |
| Manager | BNP Paribas Asset Management |
| NAV (init) | 167.34 EUR/share (on-chain: `16_734_00000000`, scaled 10⁸) |
| Oracle decimals | 8 (Chainlink fiat-feed convention) |
| Type | Standard VNAV Money Market Fund (EU 2017/1131) |

## NAV Oracle

The NAV oracle implements Chainlink's `AggregatorV3Interface` with 8 decimals (standard for fiat-denominated feeds), making it compatible with any protocol that reads Chainlink price feeds.

- **Deviation threshold** — rejects NAV updates that deviate more than 1% from the previous value (circuit breaker for erroneous feeds)
- **Minimum update interval** — prevents duplicate updates within the same period (12h default)
- **Staleness detection** — `isStale(maxAge)` flags when the oracle hasn't been updated; the token enforces `maxNavAge` on every read
- **Emergency override** — `emergencyPublishNAV(nav, reason)` lets DEFAULT_ADMIN_ROLE bypass the deviation circuit breaker in extreme market events (ECB shock, correction of a mispublished NAV), with the reason emitted on-chain for audit trail
- **Full history** — `navHistory(fromRound, toRound)` returns past NAVs with timestamps, capped at 1000 rounds per query
- **Atomic rounds** — each publish closes a round in a single tx, so `answeredInRound == roundId` by design
- **Multiple publishers** — separate `PUBLISHER_ROLE` allows dedicated NAV feed infrastructure

## Stack

- Solidity 0.8.24
- Foundry (forge, forge-std)
- OpenZeppelin Contracts v5 (ERC20, AccessControl, Pausable)
- Chainlink Contracts (AggregatorV3Interface)

## Build & Test

```bash
forge build
forge test -vv
```

**46 tests**, all passing, covering: oracle publishing, deviation checks, emergency override, staleness detection in subscribe/redeem/valuation, fund metadata, transfer restrictions, pause blocking both primary and secondary, forced redemption for KYC revocation, full lifecycle scenarios, and constructor input validation.

## Security Audit

An internal audit was performed on the initial implementation. All High and Medium findings have been remediated:

| Finding | Severity | Status |
|---------|----------|--------|
| NAV decimals/value inconsistency (167.34 vs 10⁴ scale) | 🔴 High | ✅ Fixed — migrated to Chainlink 10⁸ convention |
| Oracle staleness not enforced in subscribe/redeem | 🔴 High | ✅ Fixed — `_freshNAV()` helper with `maxNavAge` |
| `pause()` did not halt secondary market transfers | 🔴 High | ✅ Fixed — `_update` now reverts on `paused()` |
| Circuit breaker with no emergency override | 🟠 Medium | ✅ Fixed — `emergencyPublishNAV(nav, reason)` |
| Constructor did not validate `initialNav > 0` | 🟠 Medium | ✅ Fixed |
| `answeredInRound` semantics | 🟠 Medium | ✅ Documented — rounds are atomic by design |
| Deployer received all operational roles | 🟠 Medium | ✅ Fixed — Deploy script supports role separation via env vars |

The fixes are covered by 7 new tests (staleness reverts, pause-blocks-transfer, emergency override, force redeem, constructor validation).

## Live Deployment (Sepolia)

All contracts are deployed and **verified** on Sepolia testnet (post-audit, with fixes applied):

| Contract | Address | Etherscan |
|----------|---------|-----------|
| WhitelistManager | `0x595963c4A512742a67635c61bdbD68219CDCf87b` | [View](https://sepolia.etherscan.io/address/0x595963c4A512742a67635c61bdbD68219CDCf87b#code) |
| NAVOracle | `0x7D28829d9dd497362B240A5B5Cae46473370B2CA` | [View](https://sepolia.etherscan.io/address/0x7D28829d9dd497362B240A5B5Cae46473370B2CA#code) |
| PermissionedFundToken | `0xcCfEeF4C17d5639e9ABcAeEef0A0A16BCdd43C6d` | [View](https://sepolia.etherscan.io/address/0xcCfEeF4C17d5639e9ABcAeEef0A0A16BCdd43C6d#code) |

### Admin — Gnosis Safe (2-of-3 multisig)

`DEFAULT_ADMIN_ROLE` on every contract is held by a Safe smart-contract wallet on Sepolia, **not** by an EOA. This mirrors the institutional pattern used by production tokenized funds (BlackRock BUIDL, Franklin Templeton FOBXX): critical admin actions (role grants, emergency NAV publish, forced redemption) require multi-party approval.

| Role | Holder | Safe Explorer |
|------|--------|---------------|
| `DEFAULT_ADMIN_ROLE` + all operational roles | `0x3ee78467ceDf4a724a7A2B4B55344c79117b0Ff0` | [View Safe](https://app.safe.global/home?safe=sep:0x3ee78467ceDf4a724a7A2B4B55344c79117b0Ff0) |

The deployer EOA renounces every role at the end of the deployment script — it holds no residual privilege on-chain.

### Deploy Your Own

```bash
cp .env.example .env  # add PRIVATE_KEY, RPC_URL, ETHERSCAN_API_KEY

# Optional: separate operational roles (falls back to deployer if unset)
# export ADMIN_ADDRESS=0x...         # multisig recommended in production
# export COMPLIANCE_OFFICER=0x...
# export NAV_PUBLISHER=0x...
# export FUND_MANAGER=0x...

source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Chainlink AggregatorV3Interface, 8 decimals | Industry standard for fiat feeds — any DeFi protocol can consume the NAV feed |
| NAV deviation circuit breaker | Money market funds move basis points per day, not percent — large jumps signal errors |
| Emergency NAV override with on-chain reason | Real funds face extreme events (ECB decisions, market shocks); a pure circuit breaker without override freezes the oracle |
| Oracle separate from token | Separation of concerns: NAV infrastructure ≠ token logic. Mirrors real setup where NAV is computed by fund admin, not the transfer agent |
| Staleness check enforced in the token | Critical for institutional use — stale NAV means stale valuations. `maxNavAge` is a constructor param (48h default, weekend-safe) |
| Pause halts secondary market too | A regulatory freeze must stop all mouvement, not just primary |
| `forceRedeem` bypasses pause and staleness | Guarantees investors can always get funds back even during a freeze or oracle outage — restricted to admin |
| Real ISIN on-chain | Links the token to a regulated, identifiable financial product |
| Role separation at deploy | Production should split DEFAULT_ADMIN / COMPLIANCE / PUBLISHER / FUND_MANAGER across a multisig + dedicated keys |
| Permissioned on public chain | Mirrors BNP's approach: Ethereum infra + whitelist for compliance |

## Known Limitations (PoC scope)

- **Off-chain cash settlement** — `subscribe(investor, shares)` mints a fixed number of shares decided by the fund manager; the euro payment is assumed to occur off-chain through the custodian. A production system would take `cashAmount` and compute `shares = cashAmount * 10^decimals / NAV`.
- **Single-key admin** in the default deploy — the deployer receives `DEFAULT_ADMIN_ROLE` plus all operational roles. In production, `ADMIN_ADDRESS` should be a Gnosis Safe, and the operational roles split across dedicated keys (see env vars above).
- **NAV publisher is trusted** — no oracle decentralization (no signature aggregation, no multi-source median). The PoC focuses on the on-chain contract design, not on NAV sourcing.
- **No fee model, no dividends, no redemption queuing** — typical features of a production tokenized fund are out of scope.

## Author

**Armand Sechon** — Engineering student at ESILV (Pole Leonard de Vinci), active member of DeVinci Blockchain. Experience with Canton Network (ETHDenver), Solidity/Foundry, and institutional blockchain infrastructure.
