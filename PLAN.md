# Contracts Project Plan

## Overview

Smart contracts deployed on Base L2 that handle escrow, dispute resolution, and cashback distribution for Shulam payments.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      CONTRACTS                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────┐     ┌─────────────────────┐        │
│  │   ShulamEscrow.sol  │     │  CashbackVault.sol  │        │
│  │                     │     │                     │        │
│  │  - deposit()        │     │  - distribute()     │        │
│  │  - release()        │     │  - claim()          │        │
│  │  - refund()         │     │  - balance()        │        │
│  │  - dispute()        │     │                     │        │
│  └─────────────────────┘     └─────────────────────┘        │
│                                                              │
│  ┌─────────────────────┐                                    │
│  │ DisputeResolver.sol │                                    │
│  │                     │                                    │
│  │  - openDispute()    │                                    │
│  │  - resolveDispute() │                                    │
│  │  - escalate()       │                                    │
│  └─────────────────────┘                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Dependencies

| Dependency | Type | Purpose |
|------------|------|---------|
| OpenZeppelin | External | Access control, reentrancy guard |
| Foundry | Tooling | Compile, test, deploy |
| USDC | External | Base USDC contract |

---

## Milestones

### M1: Setup
- [ ] Foundry project initialization
- [ ] OpenZeppelin imports
- [ ] Base Sepolia deployment scripts
- [ ] Test USDC mock

### M2: Escrow Contract
- [ ] Deposit functionality
- [ ] Release to merchant
- [ ] Refund to buyer
- [ ] Time-locked releases

### M3: Cashback Vault
- [ ] Distribute cashback on settlement
- [ ] Buyer claim function
- [ ] Balance tracking
- [ ] Withdrawal limits

### M4: Dispute Resolution
- [ ] Open dispute window
- [ ] Evidence submission
- [ ] Resolution by admin
- [ ] Automatic resolution after timeout

### M5: Security
- [ ] Internal audit
- [ ] Code4rena audit
- [ ] Bug bounty setup
- [ ] Mainnet deployment

---

## User Stories (Gherkin)

### Epic 1: Escrow

```gherkin
Feature: Payment Escrow
  As a merchant
  I want payments held in escrow
  So that I can offer deferred or subscription payments

  Background:
    Given the ShulamEscrow contract is deployed
    And the facilitator address is authorized
    And USDC is approved for the contract

  Scenario: Deposit funds to escrow
    Given a verified payment of 100 USDC
    And the buyer address is "0xBuyer..."
    And the merchant address is "0xMerchant..."
    When the facilitator calls deposit()
    Then 100 USDC is transferred to the escrow contract
    And an escrow record is created with:
      | field    | value        |
      | buyer    | 0xBuyer...   |
      | merchant | 0xMerchant...|
      | amount   | 100 USDC     |
      | status   | held         |
    And EscrowCreated event is emitted

  Scenario: Release funds to merchant
    Given an escrow with ID "escrow_123"
    And the escrow status is "held"
    And the release conditions are met
    When the facilitator calls release("escrow_123")
    Then the merchant receives 99.25 USDC (after fee)
    And the escrow status changes to "released"
    And EscrowReleased event is emitted

  Scenario: Refund to buyer
    Given an escrow with ID "escrow_456"
    And the escrow status is "held"
    And the merchant has approved the refund
    When the facilitator calls refund("escrow_456")
    Then the buyer receives 100 USDC
    And the escrow status changes to "refunded"
    And EscrowRefunded event is emitted

  Scenario: Time-locked release
    Given an escrow with releaseTime set to 7 days from now
    When someone calls release() before 7 days
    Then the transaction reverts with "Release time not reached"
    When 7 days pass
    And someone calls release()
    Then the funds are released to the merchant

  Scenario: Prevent double release
    Given an escrow that has been released
    When someone calls release() again
    Then the transaction reverts with "Escrow already released"
```

### Epic 2: Cashback Vault

```gherkin
Feature: Buyer Cashback
  As a buyer
  I want to earn cashback on purchases
  So that I save money on future transactions

  Background:
    Given the CashbackVault contract is deployed
    And the vault has 10,000 USDC funding
    And the facilitator is authorized to distribute

  Scenario: Distribute cashback after payment
    Given a payment of 100 USDC was settled
    And the buyer address is "0xBuyer..."
    And the cashback rate is 0.25%
    When the facilitator calls distribute("0xBuyer...", 0.25 USDC)
    Then the buyer's cashback balance increases by 0.25 USDC
    And CashbackDistributed event is emitted

  Scenario: Buyer claims accumulated cashback
    Given buyer "0xBuyer..." has 10 USDC cashback balance
    When the buyer calls claim()
    Then 10 USDC is transferred to the buyer
    And the buyer's cashback balance becomes 0
    And CashbackClaimed event is emitted

  Scenario: Minimum claim threshold
    Given buyer "0xBuyer..." has 0.50 USDC cashback balance
    And the minimum claim amount is 1 USDC
    When the buyer calls claim()
    Then the transaction reverts with "Below minimum claim amount"

  Scenario: Check cashback balance
    Given buyer "0xBuyer..." has earned cashback from 5 purchases
    When anyone calls balance("0xBuyer...")
    Then the total accumulated cashback is returned

  Scenario: Prevent vault drain
    Given the vault has 100 USDC remaining
    And a distribution of 200 USDC is attempted
    When facilitator calls distribute()
    Then the transaction reverts with "Insufficient vault balance"
    And an alert is logged for operations
```

### Epic 3: Dispute Resolution

```gherkin
Feature: Payment Disputes
  As a buyer
  I want to dispute a payment
  So that I can get a refund if goods aren't delivered

  Background:
    Given the DisputeResolver contract is deployed
    And connected to the ShulamEscrow contract
    And the dispute window is 14 days

  Scenario: Open dispute within window
    Given an escrow "escrow_123" was created 5 days ago
    And the status is "held"
    When the buyer calls openDispute("escrow_123", "Item not received")
    Then a dispute record is created
    And the escrow is locked from release
    And DisputeOpened event is emitted
    And the merchant is notified

  Scenario: Open dispute after window closes
    Given an escrow "escrow_456" was created 20 days ago
    When the buyer calls openDispute("escrow_456", "Item not received")
    Then the transaction reverts with "Dispute window closed"

  Scenario: Merchant responds to dispute
    Given a dispute "dispute_123" is open
    And the merchant has 7 days to respond
    When the merchant calls respond("dispute_123", "Item was delivered", evidence_hash)
    Then the response is recorded
    And DisputeResponsed event is emitted

  Scenario: Admin resolves in buyer favor
    Given a dispute "dispute_123" with buyer and merchant responses
    When the admin calls resolve("dispute_123", "buyer")
    Then the escrow is refunded to the buyer
    And the dispute status is "resolved_buyer"
    And DisputeResolved event is emitted

  Scenario: Admin resolves in merchant favor
    Given a dispute "dispute_123" with buyer and merchant responses
    When the admin calls resolve("dispute_123", "merchant")
    Then the escrow is released to the merchant
    And the dispute status is "resolved_merchant"

  Scenario: Auto-resolve after timeout
    Given a dispute "dispute_123" has been open for 30 days
    And no admin resolution has occurred
    When anyone calls autoResolve("dispute_123")
    Then the escrow is refunded to the buyer (buyer-favored default)
    And the dispute status is "auto_resolved"
```

---

## Contract Interfaces

### IShulamEscrow

```solidity
interface IShulamEscrow {
    function deposit(
        address buyer,
        address merchant,
        uint256 amount,
        uint256 releaseTime
    ) external returns (bytes32 escrowId);
    
    function release(bytes32 escrowId) external;
    function refund(bytes32 escrowId) external;
    function getEscrow(bytes32 escrowId) external view returns (Escrow memory);
    
    event EscrowCreated(bytes32 indexed escrowId, address buyer, address merchant, uint256 amount);
    event EscrowReleased(bytes32 indexed escrowId, uint256 amount);
    event EscrowRefunded(bytes32 indexed escrowId, uint256 amount);
}
```

### ICashbackVault

```solidity
interface ICashbackVault {
    function distribute(address buyer, uint256 amount) external;
    function claim() external;
    function balance(address buyer) external view returns (uint256);
    
    event CashbackDistributed(address indexed buyer, uint256 amount);
    event CashbackClaimed(address indexed buyer, uint256 amount);
}
```

---

## Deployment Addresses

### Base Sepolia (Testnet)

| Contract | Address | Status |
|----------|---------|--------|
| ShulamEscrow | TBD | Not deployed |
| CashbackVault | TBD | Not deployed |
| DisputeResolver | TBD | Not deployed |
| USDC (Circle) | 0x036CbD53842c5426634e7929541eC2318f3dCF7e | External |

### Base Mainnet

| Contract | Address | Status |
|----------|---------|--------|
| ShulamEscrow | TBD | Not deployed |
| CashbackVault | TBD | Not deployed |
| DisputeResolver | TBD | Not deployed |
| USDC (Circle) | 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 | External |

---

## Gas Targets

| Function | Target Gas | Priority |
|----------|------------|----------|
| deposit() | < 80,000 | High |
| release() | < 60,000 | High |
| refund() | < 60,000 | High |
| distribute() | < 50,000 | Medium |
| claim() | < 50,000 | Medium |
| openDispute() | < 100,000 | Low |

---

## Security Checklist

- [ ] Reentrancy guards on all external calls
- [ ] Access control on admin functions
- [ ] Integer overflow protection (Solidity 0.8+)
- [ ] Pull over push for payments
- [ ] Emergency pause functionality
- [ ] Upgradability consideration (proxy vs immutable)

---

## Agent Instructions

### For Andrew (Developer)
1. Initialize Foundry project with `forge init`
2. Start with ShulamEscrow - simplest contract
3. Write tests before implementation
4. Use OpenZeppelin for access control

### For Thomas (QA)
1. Fuzz test all numeric inputs
2. Test reentrancy attack vectors
3. Verify events are emitted correctly
4. Test with maximum uint256 values
