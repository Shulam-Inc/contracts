# Smart Contract Security Checklist

## Pre-Deployment Checklist

### Access Control
- [ ] Only facilitator can call deposit()
- [ ] Only facilitator can call release()
- [ ] Only facilitator can call refund()
- [ ] Admin functions are protected
- [ ] No public functions that should be internal/private

### Reentrancy
- [ ] All external calls are last (CEI pattern)
- [ ] ReentrancyGuard on all state-changing functions
- [ ] No callbacks to untrusted contracts

### Integer Handling
- [ ] Using Solidity 0.8+ (built-in overflow protection)
- [ ] Fee calculations don't truncate to zero
- [ ] No precision loss in percentage calculations
- [ ] Amounts bounded to reasonable values

### Token Handling
- [ ] Using SafeERC20 for all transfers
- [ ] Handling tokens that return false instead of reverting
- [ ] Handling fee-on-transfer tokens (if applicable)
- [ ] Handling rebasing tokens (if applicable)
- [ ] USDC-specific: 6 decimals, blocklist checking

### State Management
- [ ] Escrow state transitions are one-way (held → released OR refunded)
- [ ] No way to double-release or double-refund
- [ ] Mapping keys cannot collide
- [ ] Delete storage when no longer needed (gas refund)

### Time Handling
- [ ] Using block.timestamp appropriately
- [ ] Time bounds checked correctly (>= vs >)
- [ ] No reliance on exact block times

### Events
- [ ] All state changes emit events
- [ ] Events are indexed appropriately
- [ ] Events contain enough data for off-chain tracking

### Gas Optimization
- [ ] No unbounded loops
- [ ] Storage reads minimized (cache in memory)
- [ ] Appropriate use of calldata vs memory
- [ ] Packed structs where possible

---

## Slither Findings Triage

### Must Fix (High/Medium)
- [ ] Reentrancy vulnerabilities
- [ ] Access control issues
- [ ] Integer overflow/underflow (pre-0.8)
- [ ] Unchecked return values
- [ ] Dangerous delegatecall

### Should Review (Low)
- [ ] Missing zero-address checks
- [ ] Timestamp dependence (minor)
- [ ] Costly loops
- [ ] Unused variables

### Informational (Document Decision)
- [ ] Naming conventions
- [ ] Solidity version pragma
- [ ] Function visibility

---

## Pre-Mainnet Audit Requirements

### Documentation
- [ ] NatSpec comments on all public functions
- [ ] Architecture diagram
- [ ] Threat model document
- [ ] Known limitations documented

### Testing
- [ ] Unit test coverage > 90%
- [ ] Fuzz tests for all numeric inputs
- [ ] Invariant tests for critical properties
- [ ] Fork tests against mainnet USDC

### Static Analysis
- [ ] Slither: 0 high/medium findings
- [ ] Mythril: 0 high/medium findings
- [ ] Manual review of all external calls

### Deployment
- [ ] Testnet deployed and tested
- [ ] Integration tests pass on testnet
- [ ] Gas costs documented
- [ ] Upgrade path documented (if upgradeable)

---

## External Audit Prep

### Files to Provide
- [ ] All .sol files in scope
- [ ] foundry.toml / hardhat.config
- [ ] Test suite
- [ ] Deployment scripts
- [ ] Architecture docs
- [ ] Previous audit reports (if any)

### Scope Definition
```
In Scope:
- src/ShulamEscrow.sol
- src/CashbackVault.sol
- src/interfaces/*.sol

Out of Scope:
- lib/* (external dependencies)
- test/* (test files)
- script/* (deployment scripts)
```

### Known Issues to Document
- [ ] List any accepted risks
- [ ] List any design tradeoffs
- [ ] List any centralization vectors
