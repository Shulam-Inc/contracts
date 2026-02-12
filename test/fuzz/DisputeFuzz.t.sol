// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/ShulamEscrow.sol";
import "../../src/DisputeResolver.sol";
import "../mocks/MockUSDC.sol";

/// @title DisputeFuzzTest
/// @notice Fuzz tests for DisputeResolver contract
contract DisputeFuzzTest is Test {
    ShulamEscrow escrow;
    DisputeResolver resolver;
    MockUSDC usdc;

    address facilitator = address(0xF);
    address admin = address(0xA);
    address buyer = address(0xB);
    address merchant = address(0xC);

    uint256 constant DISPUTE_WINDOW = 14 days;
    uint256 constant RESPONSE_WINDOW = 7 days;
    uint256 constant AUTO_RESOLVE_TIMEOUT = 30 days;

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ShulamEscrow(address(usdc), facilitator);
        resolver = new DisputeResolver(
            address(escrow), admin, DISPUTE_WINDOW, RESPONSE_WINDOW, AUTO_RESOLVE_TIMEOUT
        );
        vm.prank(facilitator);
        escrow.setDisputeResolver(address(resolver));
    }

    // --- Fuzz: dispute within window always succeeds ---

    function testFuzz_OpenDisputeWithinWindow(uint256 amount, uint256 timeElapsed) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        timeElapsed = bound(timeElapsed, 0, DISPUTE_WINDOW);

        usdc.mint(address(escrow), amount);
        bytes32 escrowId = keccak256(abi.encodePacked("dispute-fuzz", amount));

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, amount, 0);

        vm.warp(block.timestamp + timeElapsed);

        vm.prank(buyer);
        bytes32 disputeId = resolver.openDispute(escrowId, "Test dispute");

        DisputeResolver.Dispute memory d = resolver.getDispute(disputeId);
        assertEq(d.buyer, buyer);
        assertEq(d.merchant, merchant);
        assertTrue(d.resolution == DisputeResolver.Resolution.None);
    }

    // --- Fuzz: dispute after window always reverts ---

    function testFuzz_OpenDisputeAfterWindow(uint256 amount, uint256 timeElapsed) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        timeElapsed = bound(timeElapsed, DISPUTE_WINDOW + 1, DISPUTE_WINDOW + 365 days);

        usdc.mint(address(escrow), amount);
        bytes32 escrowId = keccak256(abi.encodePacked("dispute-late", amount));

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, amount, 0);

        vm.warp(block.timestamp + timeElapsed);

        vm.prank(buyer);
        vm.expectRevert(DisputeResolver.DisputeWindowClosed.selector);
        resolver.openDispute(escrowId, "Too late");
    }

    // --- Fuzz: only buyer can open dispute ---

    function testFuzz_OpenDispute_OnlyBuyer(address caller) public {
        vm.assume(caller != buyer);

        usdc.mint(address(escrow), 100e6);
        bytes32 escrowId = keccak256("buyer-only");

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, 100e6, 0);

        vm.prank(caller);
        vm.expectRevert(DisputeResolver.Unauthorized.selector);
        resolver.openDispute(escrowId, "Not my escrow");
    }

    // --- Fuzz: only admin can resolve ---

    function testFuzz_Resolve_OnlyAdmin(address caller, bool favorBuyer) public {
        vm.assume(caller != admin);

        usdc.mint(address(escrow), 100e6);
        bytes32 escrowId = keccak256("admin-only");

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, 100e6, 0);

        vm.prank(buyer);
        bytes32 disputeId = resolver.openDispute(escrowId, "Dispute");

        vm.prank(caller);
        vm.expectRevert(DisputeResolver.Unauthorized.selector);
        resolver.resolve(disputeId, favorBuyer);
    }

    // --- Fuzz: buyer-favored resolution always refunds full amount ---

    function testFuzz_ResolveBuyerFavored(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 escrowId = keccak256(abi.encodePacked("buyer-favor", amount));

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, amount, 0);

        vm.prank(buyer);
        bytes32 disputeId = resolver.openDispute(escrowId, "Dispute");

        vm.prank(admin);
        resolver.resolve(disputeId, true);

        assertEq(usdc.balanceOf(buyer), amount);
        assertEq(usdc.balanceOf(merchant), 0);
    }

    // --- Fuzz: merchant-favored resolution always releases full amount ---

    function testFuzz_ResolveMerchantFavored(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        usdc.mint(address(escrow), amount);
        bytes32 escrowId = keccak256(abi.encodePacked("merchant-favor", amount));

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, amount, 0);

        vm.prank(buyer);
        bytes32 disputeId = resolver.openDispute(escrowId, "Dispute");

        vm.prank(admin);
        resolver.resolve(disputeId, false);

        assertEq(usdc.balanceOf(merchant), amount);
        assertEq(usdc.balanceOf(buyer), 0);
    }

    // --- Fuzz: auto-resolve always refunds buyer after timeout ---

    function testFuzz_AutoResolve(uint256 amount, uint256 extraTime) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        extraTime = bound(extraTime, 0, 365 days);

        usdc.mint(address(escrow), amount);
        bytes32 escrowId = keccak256(abi.encodePacked("auto-resolve", amount));

        vm.prank(facilitator);
        escrow.deposit(escrowId, buyer, merchant, amount, 0);

        vm.prank(buyer);
        bytes32 disputeId = resolver.openDispute(escrowId, "Dispute");

        vm.warp(block.timestamp + AUTO_RESOLVE_TIMEOUT + extraTime);

        resolver.autoResolve(disputeId);

        assertEq(usdc.balanceOf(buyer), amount);
        assertTrue(
            resolver.getDispute(disputeId).resolution == DisputeResolver.Resolution.AutoResolved
        );
    }
}
