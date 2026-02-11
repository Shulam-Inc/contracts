// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

/**
 * @title EscrowInvariantTest
 * @notice Invariant tests for ShulamEscrow contract
 * @dev These tests ensure critical properties always hold
 */
abstract contract EscrowInvariantTest is StdInvariant, Test {
    
    // =============================================================
    //                        INVARIANTS
    // =============================================================
    
    /**
     * @notice Contract balance must always equal sum of all held escrows
     * @dev This ensures no funds are lost or created
     */
    function invariant_balanceEqualsHeldEscrows() public view virtual;
    
    /**
     * @notice An escrow can only be in one state at a time
     * @dev States: Held, Released, Refunded, Disputed
     */
    function invariant_escrowStateExclusive() public view virtual;
    
    /**
     * @notice Released + Refunded escrow amounts cannot exceed total deposits
     * @dev Prevents double-spend scenarios
     */
    function invariant_noDoubleSpend() public view virtual;
    
    /**
     * @notice Total fees collected must equal sum of individual fees
     * @dev Ensures fee accounting is correct
     */
    function invariant_feeAccountingCorrect() public view virtual;
}

/**
 * @title CashbackInvariantTest  
 * @notice Invariant tests for CashbackVault contract
 */
abstract contract CashbackInvariantTest is StdInvariant, Test {
    
    /**
     * @notice Vault balance must always be >= sum of unclaimed cashback
     * @dev Ensures vault can always pay out claims
     */
    function invariant_vaultSolvent() public view virtual;
    
    /**
     * @notice Total distributed cashback must equal sum of individual distributions
     * @dev Accounting integrity check
     */
    function invariant_distributionAccountingCorrect() public view virtual;
    
    /**
     * @notice Claimed amounts cannot exceed distributed amounts per user
     * @dev Prevents over-claiming
     */
    function invariant_noOverClaim() public view virtual;
}
