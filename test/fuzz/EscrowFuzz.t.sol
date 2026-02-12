// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/ShulamEscrow.sol";
import "../mocks/MockUSDC.sol";

/// @title EscrowFuzzTest
/// @notice Fuzz tests for ShulamEscrow contract
/// @dev Run with: forge test --match-contract EscrowFuzzTest --fuzz-runs 10000
contract EscrowFuzzTest is Test {
    ShulamEscrow escrow;
    MockUSDC usdc;

    address facilitator = address(0xF);
    address buyer = address(0xB);
    address merchant = address(0xC);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ShulamEscrow(address(usdc), facilitator);
    }

    // --- Fuzz: deposit with arbitrary amounts ---

    function testFuzz_Deposit_ArbitraryAmount(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 id = keccak256(abi.encodePacked(amount));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, 0);

        ShulamEscrow.Escrow memory e = escrow.getEscrow(id);
        assertEq(e.amount, amount);
        assertEq(e.buyer, buyer);
        assertEq(e.merchant, merchant);
        assertTrue(e.status == ShulamEscrow.Status.Held);
        assertEq(escrow.totalEscrowed(), amount);
    }

    // --- Fuzz: deposit then release preserves accounting ---

    function testFuzz_DepositThenRelease(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 id = keccak256(abi.encodePacked("release", amount));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, 0);

        vm.prank(facilitator);
        escrow.release(id);

        assertEq(escrow.totalEscrowed(), 0);
        assertEq(usdc.balanceOf(merchant), amount);
        assertTrue(escrow.getEscrow(id).status == ShulamEscrow.Status.Released);
    }

    // --- Fuzz: deposit then refund preserves accounting ---

    function testFuzz_DepositThenRefund(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 id = keccak256(abi.encodePacked("refund", amount));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, 0);

        vm.prank(facilitator);
        escrow.refund(id);

        assertEq(escrow.totalEscrowed(), 0);
        assertEq(usdc.balanceOf(buyer), amount);
        assertTrue(escrow.getEscrow(id).status == ShulamEscrow.Status.Refunded);
    }

    // --- Fuzz: unauthorized callers always revert ---

    function testFuzz_Deposit_Unauthorized(address caller) public {
        vm.assume(caller != facilitator);

        usdc.mint(address(escrow), 100e6);
        bytes32 id = keccak256(abi.encodePacked("unauth", caller));

        vm.prank(caller);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.deposit(id, buyer, merchant, 100e6, 0);
    }

    function testFuzz_Refund_Unauthorized(address caller) public {
        vm.assume(caller != facilitator);

        usdc.mint(address(escrow), 100e6);
        bytes32 id = keccak256("refund-unauth");

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, 100e6, 0);

        vm.prank(caller);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.refund(id);
    }

    function testFuzz_Release_Unauthorized(address caller) public {
        vm.assume(caller != facilitator);
        vm.assume(caller != merchant);

        usdc.mint(address(escrow), 100e6);
        bytes32 id = keccak256("release-unauth");

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, 100e6, 0);

        vm.prank(caller);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.release(id);
    }

    // --- Fuzz: unique escrowIds never collide ---

    function testFuzz_UniqueIds(uint256 salt1, uint256 salt2) public {
        vm.assume(salt1 != salt2);

        bytes32 id1 = keccak256(abi.encodePacked(salt1));
        bytes32 id2 = keccak256(abi.encodePacked(salt2));

        usdc.mint(address(escrow), 200e6);

        vm.startPrank(facilitator);
        escrow.deposit(id1, buyer, merchant, 100e6, 0);
        escrow.deposit(id2, buyer, merchant, 100e6, 0);
        vm.stopPrank();

        assertEq(escrow.totalEscrowed(), 200e6);

        vm.prank(facilitator);
        escrow.release(id1);

        vm.prank(facilitator);
        escrow.refund(id2);

        assertEq(escrow.totalEscrowed(), 0);
        assertTrue(escrow.getEscrow(id1).status == ShulamEscrow.Status.Released);
        assertTrue(escrow.getEscrow(id2).status == ShulamEscrow.Status.Refunded);
    }

    // --- Fuzz: merchant can release their own escrow ---

    function testFuzz_Release_ByMerchant(address merchantAddr) public {
        vm.assume(merchantAddr != address(0));
        vm.assume(merchantAddr != address(escrow));
        vm.assume(merchantAddr != buyer);

        usdc.mint(address(escrow), 50e6);
        bytes32 id = keccak256(abi.encodePacked("merchant-release", merchantAddr));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchantAddr, 50e6, 0);

        vm.prank(merchantAddr);
        escrow.release(id);

        assertTrue(escrow.getEscrow(id).status == ShulamEscrow.Status.Released);
        assertEq(usdc.balanceOf(merchantAddr), 50e6);
    }

    // --- Fuzz: double-settle always reverts ---

    function testFuzz_DoubleRelease_Reverts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 id = keccak256(abi.encodePacked("double-release", amount));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, 0);

        vm.prank(facilitator);
        escrow.release(id);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowAlreadySettled.selector);
        escrow.release(id);
    }

    function testFuzz_RefundAfterRelease_Reverts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 id = keccak256(abi.encodePacked("refund-after-release", amount));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, 0);

        vm.prank(facilitator);
        escrow.release(id);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowAlreadySettled.selector);
        escrow.refund(id);
    }

    // --- Fuzz: time-locked release ---

    function testFuzz_CannotReleaseTooEarly(uint256 amount, uint256 releaseTime) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        releaseTime = bound(releaseTime, block.timestamp + 1 hours, block.timestamp + 365 days);

        usdc.mint(address(escrow), amount);
        bytes32 id = keccak256(abi.encodePacked("timelock", amount, releaseTime));

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, releaseTime);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.ReleaseTooEarly.selector);
        escrow.release(id);

        // Warp to release time — now it should succeed
        vm.warp(releaseTime);
        vm.prank(facilitator);
        escrow.release(id);

        assertTrue(escrow.getEscrow(id).status == ShulamEscrow.Status.Released);
    }

    // --- Edge cases ---

    function test_MinimumDeposit() public {
        usdc.mint(address(escrow), 1);
        bytes32 id = keccak256("min-deposit");

        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, 1, 0);

        assertEq(escrow.getEscrow(id).amount, 1);
    }

    function test_ZeroAddressReverts() public {
        usdc.mint(address(escrow), 100e6);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        escrow.deposit(keccak256("zero-buyer"), address(0), merchant, 100e6, 0);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        escrow.deposit(keccak256("zero-merchant"), buyer, address(0), 100e6, 0);
    }
}
