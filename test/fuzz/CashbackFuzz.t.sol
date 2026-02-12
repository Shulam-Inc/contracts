// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/CashbackVault.sol";
import "../mocks/MockUSDC.sol";

/// @title CashbackFuzzTest
/// @notice Fuzz tests for CashbackVault contract
contract CashbackFuzzTest is Test {
    CashbackVault vault;
    MockUSDC usdc;

    address facilitator = address(0xF);
    address buyer = address(0xB);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new CashbackVault(address(usdc), facilitator, 0); // no minimum for fuzz tests
    }

    // --- Fuzz: credit arbitrary amounts ---

    function testFuzz_Credit_ArbitraryAmount(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(vault), amount);

        vm.prank(facilitator);
        vault.credit(buyer, amount);

        assertEq(vault.balanceOf(buyer), amount);
        assertEq(vault.totalAccrued(), amount);
    }

    // --- Fuzz: credit then full withdraw ---

    function testFuzz_CreditThenWithdraw(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(vault), amount);

        vm.prank(facilitator);
        vault.credit(buyer, amount);

        vm.prank(buyer);
        vault.withdraw(buyer, amount);

        assertEq(vault.balanceOf(buyer), 0);
        assertEq(vault.totalAccrued(), 0);
        assertEq(usdc.balanceOf(buyer), amount);
    }

    // --- Fuzz: partial withdraw ---

    function testFuzz_PartialWithdraw(uint256 creditAmount, uint256 withdrawAmount) public {
        vm.assume(creditAmount > 0);
        vm.assume(creditAmount <= type(uint128).max);
        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount < creditAmount);

        usdc.mint(address(vault), creditAmount);

        vm.prank(facilitator);
        vault.credit(buyer, creditAmount);

        vm.prank(buyer);
        vault.withdraw(buyer, withdrawAmount);

        assertEq(vault.balanceOf(buyer), creditAmount - withdrawAmount);
        assertEq(vault.totalAccrued(), creditAmount - withdrawAmount);
        assertEq(usdc.balanceOf(buyer), withdrawAmount);
    }

    // --- Fuzz: unauthorized callers cannot credit ---

    function testFuzz_Credit_Unauthorized(address caller) public {
        vm.assume(caller != facilitator);

        usdc.mint(address(vault), 100e6);

        vm.prank(caller);
        vm.expectRevert(CashbackVault.Unauthorized.selector);
        vault.credit(buyer, 100e6);
    }

    // --- Fuzz: unauthorized callers cannot withdraw ---

    function testFuzz_Withdraw_Unauthorized(address caller) public {
        vm.assume(caller != buyer);
        vm.assume(caller != facilitator);

        usdc.mint(address(vault), 100e6);

        vm.prank(facilitator);
        vault.credit(buyer, 100e6);

        vm.prank(caller);
        vm.expectRevert(CashbackVault.Unauthorized.selector);
        vault.withdraw(buyer, 100e6);
    }

    // --- Fuzz: buyer can always withdraw their own balance ---

    function testFuzz_Withdraw_ByBuyer(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(vault), amount);

        vm.prank(facilitator);
        vault.credit(buyer, amount);

        vm.prank(buyer);
        vault.withdraw(buyer, amount);

        assertEq(vault.balanceOf(buyer), 0);
        assertEq(usdc.balanceOf(buyer), amount);
    }

    // --- Fuzz: facilitator can always withdraw on behalf ---

    function testFuzz_Withdraw_ByFacilitator(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(vault), amount);

        vm.prank(facilitator);
        vault.credit(buyer, amount);

        vm.prank(facilitator);
        vault.withdraw(buyer, amount);

        assertEq(vault.balanceOf(buyer), 0);
        assertEq(usdc.balanceOf(buyer), amount);
    }

    // --- Fuzz: multiple credits accumulate ---

    function testFuzz_MultipleCredits(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 > 0);
        vm.assume(amount2 > 0);
        vm.assume(amount1 <= type(uint128).max / 2);
        vm.assume(amount2 <= type(uint128).max / 2);

        usdc.mint(address(vault), amount1 + amount2);

        vm.prank(facilitator);
        vault.credit(buyer, amount1);

        vm.prank(facilitator);
        vault.credit(buyer, amount2);

        assertEq(vault.balanceOf(buyer), amount1 + amount2);
        assertEq(vault.totalAccrued(), amount1 + amount2);
    }

    // --- Fuzz: withdrawing more than balance reverts ---

    function testFuzz_WithdrawExceedsBalance_Reverts(uint256 creditAmount, uint256 withdrawAmount) public {
        vm.assume(creditAmount > 0);
        vm.assume(creditAmount <= type(uint128).max);
        vm.assume(withdrawAmount > creditAmount);
        vm.assume(withdrawAmount <= type(uint128).max);

        usdc.mint(address(vault), creditAmount);

        vm.prank(facilitator);
        vault.credit(buyer, creditAmount);

        vm.prank(buyer);
        vm.expectRevert(CashbackVault.InsufficientBalance.selector);
        vault.withdraw(buyer, withdrawAmount);
    }
}
