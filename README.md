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

## Live Deployment (Sepolia)

All contracts are deployed and **verified** on Sepolia testnet:

| Contract | Address | Etherscan |
|----------|---------|-----------|
| WhitelistManager | `0x5301118e505FE55d4966449320EbE4E6c67e2B7F` | [View](https://sepolia.etherscan.io/address/0x5301118e505FE55d4966449320EbE4E6c67e2B7F#code) |
| NAVOracle | `0xbeDE0b420d8a91c4fFea8df830652C2C591545E4` | [View](https://sepolia.etherscan.io/address/0xbeDE0b420d8a91c4fFea8df830652C2C591545E4#code) |
| PermissionedFundToken | `0x19A7E8bf5722d59A2B6f723AA3b0D03518707c0a` | [View](https://sepolia.etherscan.io/address/0x19A7E8bf5722d59A2B6f723AA3b0D03518707c0a#code) |

### On-chain Activity

Live transactions demonstrating the full fund lifecycle:

| Step | Transaction | Description |
|------|-------------|-------------|
| KYC onboarding | [`0xa2772...`](https://sepolia.etherscan.io/tx/0xa27720007f2fb83e38ea568751d0db3a3f310cb6ed5adf6e54f9e496f81cfaa3) | Batch whitelist 2 institutional investors |
| Subscription | [`0x48f5a...`](https://sepolia.etherscan.io/tx/0x48f5aa6bf4423246e8fd133e77f28e56ef5557dab4e87440b9672e0a0e23363f) | 500 shares minted at NAV 167.34 EUR |
| Subscription | [`0xb7fa3...`](https://sepolia.etherscan.io/tx/0xb7fa32adea92beec4426551e63dc11ebf459f85a4787796cbfa2d9c96d7ff25f) | 200 shares to investor A |
| Subscription | [`0x93883...`](https://sepolia.etherscan.io/tx/0x938833126270cadc684d3a7676c6b60a1af82c6f980907fa5a75aefe4edf62a5) | 100 shares to investor B |
| Redemption | [`0x97635...`](https://sepolia.etherscan.io/tx/0x97635d8abc49e1b22dbc4b6d1921fb43d6006c93cbf3b613fc94e587a1b382aa) | 50 shares burned (partial redemption) |
| Secondary market | [`0x7d43c...`](https://sepolia.etherscan.io/tx/0x7d43c355d10eee45d9d897e3dace126e846f7aa76c30276f9068be016b467921) | 30 shares transferred between whitelisted investors |

**Current state:** 750 tMMF-EUR shares in circulation across 3 whitelisted addresses.

### Deploy Your Own

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
