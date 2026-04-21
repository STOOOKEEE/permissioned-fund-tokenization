# Tokenized Fund PoC — BNP Paribas Euro Money Market on Ethereum

Proof-of-concept tokenizing shares of the [BNP Paribas Euro Money Market fund](https://www.bnpparibas-am.com/en-be/fundsheet/marche-monetaire/bnp-paribas-funds-euro-money-market-classic-d-lu0083137926/) (ISIN: LU0083138064) on public Ethereum with permissioned transfers and a Chainlink-compatible NAV oracle.

## Context

In February 2026, BNP Paribas Asset Management [issued tokenized shares](https://group.bnpparibas/en/press-release/bnp-paribas-explores-public-blockchain-infrastructure-for-money-market-fund-tokenisation) of a French money market fund on public Ethereum via their AssetFoundry platform. This PoC demonstrates how such a tokenization could work technically, including the NAV feed problem — how does the daily Net Asset Value reach the blockchain in a verifiable, auditable way?

## Architecture

```
NAVOracle (Chainlink AggregatorV3Interface)
├── PUBLISHER_ROLE can push daily NAV
├── deviation check (max 1% per update)
├── staleness detection
├── full round history
└── consumed by PermissionedFundToken

WhitelistManager
├── COMPLIANCE_ROLE
├── addInvestor() / removeInvestor()
└── addInvestorsBatch()

PermissionedFundToken (tMMF-EUR)
├── reads NAV from oracle on every subscribe/redeem
├── subscribe() → mint to whitelisted investor at oracle NAV
├── redeem() → burn shares at oracle NAV
├── shareValueInCurrency() → portfolio valuation from live oracle
├── pause() / unpause() → regulatory freeze
└── _update() → enforces whitelist on every transfer
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
| NAV (init) | 167.34 EUR/share |
| Type | Standard VNAV Money Market Fund (EU 2017/1131) |

## NAV Oracle

The NAV oracle implements Chainlink's `AggregatorV3Interface`, making it compatible with any protocol that reads Chainlink price feeds. Features:

- **Deviation threshold** — rejects NAV updates that deviate more than 1% from the previous value (circuit breaker for erroneous feeds)
- **Minimum update interval** — prevents duplicate updates within the same period (12h default)
- **Staleness detection** — `isStale(maxAge)` flags when the oracle hasn't been updated
- **Full history** — `navHistory(fromRound, toRound)` returns all past NAVs with timestamps
- **Multiple publishers** — separate `PUBLISHER_ROLE` allows dedicated NAV feed infrastructure

## Stack

- Solidity 0.8.24
- Foundry (forge, forge-std)
- OpenZeppelin Contracts v5 (ERC20, AccessControl, Pausable)
- Chainlink Contracts (AggregatorV3Interface)

## Build & Test

```bash
forge build
forge test -v
```

30 tests covering: oracle publishing, deviation checks, staleness, history, fund metadata, subscriptions at oracle NAV, redemptions, transfer restrictions, share valuation, pause/unpause, full lifecycle scenarios, regulatory freeze, KYC revocation.

## Deploy (Sepolia)

```bash
cp .env.example .env  # add PRIVATE_KEY, RPC_URL, ETHERSCAN_API_KEY
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Chainlink AggregatorV3Interface | Industry standard — any DeFi protocol can consume the NAV feed |
| NAV deviation circuit breaker | Money market funds move basis points per day, not percent — large jumps signal errors |
| Oracle separate from token | Separation of concerns: NAV infrastructure ≠ token logic. Mirrors real setup where NAV is computed by fund admin, not the transfer agent |
| Staleness check | Critical for institutional use — stale NAV means stale valuations |
| Real ISIN on-chain | Links the token to a regulated, identifiable financial product |
| Permissioned on public chain | Mirrors BNP's approach: Ethereum infra + whitelist for compliance |

## Author

**Armand Sechon** — Engineering student at ESILV (Pole Leonard de Vinci), active member of DeVinci Blockchain. Experience with Canton Network (ETHDenver), Solidity/Foundry, and institutional blockchain infrastructure.
