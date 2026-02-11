# Shulam Contracts

Smart contracts for escrow, dispute resolution, and cashback distribution.

## Overview

Solidity contracts deployed on Base L2 that handle edge cases beyond standard x402 direct payments.

## Contracts

| Contract | Purpose |
|----------|---------|
| `ShulamEscrow.sol` | Holds funds for deferred/subscription payments |
| `CashbackVault.sol` | Distributes buyer cashback rewards |
| `DisputeResolver.sol` | Handles payment disputes and refunds |

## Architecture

```
contracts/
├── core/
│   ├── ShulamEscrow.sol
│   ├── CashbackVault.sol
│   └── DisputeResolver.sol
├── interfaces/
│   ├── IShulamEscrow.sol
│   └── ICashbackVault.sol
├── libraries/
│   └── PaymentLib.sol
└── mocks/
    └── MockUSDC.sol
```

## Deployment Addresses

### Base Sepolia (Testnet)

| Contract | Address |
|----------|---------|
| ShulamEscrow | `0x...` |
| CashbackVault | `0x...` |
| USDC (test) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

### Base Mainnet

| Contract | Address |
|----------|---------|
| ShulamEscrow | TBD |
| CashbackVault | TBD |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |

## Development

```bash
# Install dependencies
npm install

# Compile contracts
npm run compile

# Run tests
npm test

# Deploy to testnet
npm run deploy:testnet

# Verify on Basescan
npm run verify
```

## Tech Stack

- Solidity 0.8.20
- Foundry (forge, cast, anvil)
- OpenZeppelin Contracts
- Base L2

## Security

- [ ] Internal audit complete
- [ ] External audit (Code4rena) — scheduled for Phase 5
- [ ] Bug bounty program — post-mainnet

## Gas Optimization

Target gas costs:
- Escrow deposit: < 80,000 gas
- Escrow release: < 60,000 gas
- Cashback claim: < 50,000 gas

## License

Proprietary — Shulam, Inc.
