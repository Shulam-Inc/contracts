// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CashbackVault.sol";
import "./mocks/MockUSDC.sol";

contract CashbackVaultTest is Test {
    CashbackVault vault;
    MockUSDC usdc;

    address facilitator = address(0xF);
    address buyer = address(0xB);
    address buyer2 = address(0xB2);
    address random = address(0xD);

    uint256 constant MIN_CLAIM = 1e6; // 1 USDC

    event Credited(address indexed buyer, uint256 amount);
    event Withdrawn(address indexed buyer, uint256 amount);
    event MinimumClaimUpdated(uint256 oldAmount, uint256 newAmount);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new CashbackVault(address(usdc), facilitator, MIN_CLAIM);
    }

    // --- Constructor ---

    function test_Constructor_ZeroUsdc() public {
        vm.expectRevert(CashbackVault.InvalidAddress.selector);
        new CashbackVault(address(0), facilitator, MIN_CLAIM);
    }

    function test_Constructor_ZeroFacilitator() public {
        vm.expectRevert(CashbackVault.InvalidAddress.selector);
        new CashbackVault(address(usdc), address(0), MIN_CLAIM);
    }

    function test_Constructor_SetsMinimumClaim() public {
        assertEq(vault.minimumClaim(), MIN_CLAIM);
    }

    // --- Credit ---

    function test_Credit_Success() public {
        usdc.mint(address(vault), 1e6);

        vm.prank(facilitator);
        vault.credit(buyer, 0.25e6);

        assertEq(vault.balanceOf(buyer), 0.25e6);
        assertEq(vault.totalAccrued(), 0.25e6);
    }

    function test_Credit_EmitsEvent() public {
        usdc.mint(address(vault), 1e6);

        vm.expectEmit(true, false, false, true);
        emit Credited(buyer, 0.25e6);

        vm.prank(facilitator);
        vault.credit(buyer, 0.25e6);
    }

    function test_Credit_Unauthorized() public {
        usdc.mint(address(vault), 1e6);

        vm.prank(random);
        vm.expectRevert(CashbackVault.Unauthorized.selector);
        vault.credit(buyer, 0.25e6);
    }

    function test_Credit_InvalidAmount() public {
        vm.prank(facilitator);
        vm.expectRevert(CashbackVault.InvalidAmount.selector);
        vault.credit(buyer, 0);
    }

    function test_Credit_ZeroBuyer() public {
        usdc.mint(address(vault), 1e6);
        vm.prank(facilitator);
        vm.expectRevert(CashbackVault.InvalidAddress.selector);
        vault.credit(address(0), 0.25e6);
    }

    function test_Credit_InsufficientBalance() public {
        vm.prank(facilitator);
        vm.expectRevert(CashbackVault.InsufficientBalance.selector);
        vault.credit(buyer, 0.25e6);
    }

    function test_MultipleCredits() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 0.25e6);

        vm.prank(facilitator);
        vault.credit(buyer, 0.50e6);

        vm.prank(facilitator);
        vault.credit(buyer2, 1e6);

        assertEq(vault.balanceOf(buyer), 0.75e6);
        assertEq(vault.balanceOf(buyer2), 1e6);
        assertEq(vault.totalAccrued(), 1.75e6);
    }

    // --- Withdraw ---

    function test_Withdraw_ByBuyer() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.prank(buyer);
        vault.withdraw(buyer, 5e6);

        assertEq(vault.balanceOf(buyer), 0);
        assertEq(vault.totalAccrued(), 0);
        assertEq(usdc.balanceOf(buyer), 5e6);
    }

    function test_Withdraw_ByFacilitator() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.prank(facilitator);
        vault.withdraw(buyer, 5e6);

        assertEq(vault.balanceOf(buyer), 0);
        assertEq(usdc.balanceOf(buyer), 5e6);
    }

    function test_Withdraw_EmitsEvent() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(buyer, 5e6);

        vm.prank(buyer);
        vault.withdraw(buyer, 5e6);
    }

    function test_Withdraw_Unauthorized() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.prank(random);
        vm.expectRevert(CashbackVault.Unauthorized.selector);
        vault.withdraw(buyer, 5e6);
    }

    function test_Withdraw_InvalidAmount() public {
        vm.prank(buyer);
        vm.expectRevert(CashbackVault.InvalidAmount.selector);
        vault.withdraw(buyer, 0);
    }

    function test_Withdraw_InsufficientBalance() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.prank(buyer);
        vm.expectRevert(CashbackVault.InsufficientBalance.selector);
        vault.withdraw(buyer, 10e6);
    }

    function test_Withdraw_Partial() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.prank(buyer);
        vault.withdraw(buyer, 2e6);

        assertEq(vault.balanceOf(buyer), 3e6);
        assertEq(vault.totalAccrued(), 3e6);
        assertEq(usdc.balanceOf(buyer), 2e6);
    }

    function test_Withdraw_BelowMinimumClaim() public {
        usdc.mint(address(vault), 10e6);

        vm.prank(facilitator);
        vault.credit(buyer, 5e6);

        vm.prank(buyer);
        vm.expectRevert(CashbackVault.BelowMinimumClaim.selector);
        vault.withdraw(buyer, 0.5e6); // below 1 USDC minimum
    }

    // --- setMinimumClaim ---

    function test_SetMinimumClaim() public {
        vm.expectEmit(false, false, false, true);
        emit MinimumClaimUpdated(MIN_CLAIM, 2e6);

        vm.prank(facilitator);
        vault.setMinimumClaim(2e6);

        assertEq(vault.minimumClaim(), 2e6);
    }

    function test_SetMinimumClaim_Unauthorized() public {
        vm.prank(random);
        vm.expectRevert(CashbackVault.Unauthorized.selector);
        vault.setMinimumClaim(2e6);
    }
}
