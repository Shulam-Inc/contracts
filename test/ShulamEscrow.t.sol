// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ShulamEscrow.sol";
import "./mocks/MockUSDC.sol";

contract ShulamEscrowTest is Test {
    ShulamEscrow escrow;
    MockUSDC usdc;

    address facilitator = address(0xF);
    address buyer = address(0xB);
    address merchant = address(0xC);
    address random = address(0xD);

    bytes32 escrowId1 = keccak256("escrow-1");
    bytes32 escrowId2 = keccak256("escrow-2");

    event Deposited(bytes32 indexed escrowId, address indexed buyer, address indexed merchant, uint256 amount);
    event Released(bytes32 indexed escrowId, address indexed merchant, uint256 amount);
    event Refunded(bytes32 indexed escrowId, address indexed buyer, uint256 amount);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ShulamEscrow(address(usdc), facilitator);
    }

    // Helper: deposit with default release time (immediate)
    function _deposit(bytes32 id, address _buyer, address _merchant, uint256 amount) internal {
        usdc.mint(address(escrow), amount);
        vm.prank(facilitator);
        escrow.deposit(id, _buyer, _merchant, amount, 0);
    }

    // --- Constructor ---

    function test_Constructor_ZeroUsdc() public {
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        new ShulamEscrow(address(0), facilitator);
    }

    function test_Constructor_ZeroFacilitator() public {
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        new ShulamEscrow(address(usdc), address(0));
    }

    // --- Deposit ---

    function test_Deposit_Success() public {
        usdc.mint(address(escrow), 100e6);

        vm.prank(facilitator);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, 0);

        ShulamEscrow.Escrow memory e = escrow.getEscrow(escrowId1);
        assertEq(e.buyer, buyer);
        assertEq(e.merchant, merchant);
        assertEq(e.amount, 100e6);
        assertTrue(e.status == ShulamEscrow.Status.Held);
        assertEq(escrow.totalEscrowed(), 100e6);
    }

    function test_Deposit_EmitsEvent() public {
        usdc.mint(address(escrow), 100e6);

        vm.expectEmit(true, true, true, true);
        emit Deposited(escrowId1, buyer, merchant, 100e6);

        vm.prank(facilitator);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, 0);
    }

    function test_Deposit_WithReleaseTime() public {
        usdc.mint(address(escrow), 100e6);

        uint256 releaseTime = block.timestamp + 7 days;
        vm.prank(facilitator);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, releaseTime);

        ShulamEscrow.Escrow memory e = escrow.getEscrow(escrowId1);
        assertEq(e.releaseTime, releaseTime);
    }

    function test_Deposit_Unauthorized() public {
        usdc.mint(address(escrow), 100e6);

        vm.prank(random);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, 0);
    }

    function test_Deposit_InvalidAmount() public {
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAmount.selector);
        escrow.deposit(escrowId1, buyer, merchant, 0, 0);
    }

    function test_Deposit_ZeroBuyer() public {
        usdc.mint(address(escrow), 100e6);
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        escrow.deposit(escrowId1, address(0), merchant, 100e6, 0);
    }

    function test_Deposit_ZeroMerchant() public {
        usdc.mint(address(escrow), 100e6);
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        escrow.deposit(escrowId1, buyer, address(0), 100e6, 0);
    }

    function test_Deposit_BuyerEqualsMerchant() public {
        usdc.mint(address(escrow), 100e6);
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        escrow.deposit(escrowId1, buyer, buyer, 100e6, 0);
    }

    function test_Deposit_Duplicate() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        usdc.mint(address(escrow), 100e6);
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowAlreadySettled.selector);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, 0);
    }

    function test_Deposit_InsufficientBalance() public {
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InsufficientBalance.selector);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, 0);
    }

    // --- Release ---

    function test_Release_ByFacilitator() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(facilitator);
        escrow.release(escrowId1);

        ShulamEscrow.Escrow memory e = escrow.getEscrow(escrowId1);
        assertTrue(e.status == ShulamEscrow.Status.Released);
        assertEq(usdc.balanceOf(merchant), 100e6);
        assertEq(escrow.totalEscrowed(), 0);
    }

    function test_Release_ByMerchant() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(merchant);
        escrow.release(escrowId1);

        ShulamEscrow.Escrow memory e = escrow.getEscrow(escrowId1);
        assertTrue(e.status == ShulamEscrow.Status.Released);
        assertEq(usdc.balanceOf(merchant), 100e6);
    }

    function test_Release_EmitsEvent() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.expectEmit(true, true, false, true);
        emit Released(escrowId1, merchant, 100e6);

        vm.prank(facilitator);
        escrow.release(escrowId1);
    }

    function test_Release_NotFound() public {
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowNotFound.selector);
        escrow.release(escrowId1);
    }

    function test_Release_Unauthorized() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(random);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.release(escrowId1);
    }

    function test_Release_AlreadySettled() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(facilitator);
        escrow.release(escrowId1);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowAlreadySettled.selector);
        escrow.release(escrowId1);
    }

    function test_Release_TooEarly() public {
        usdc.mint(address(escrow), 100e6);
        uint256 releaseTime = block.timestamp + 7 days;

        vm.prank(facilitator);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, releaseTime);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.ReleaseTooEarly.selector);
        escrow.release(escrowId1);
    }

    function test_Release_AfterReleaseTime() public {
        usdc.mint(address(escrow), 100e6);
        uint256 releaseTime = block.timestamp + 7 days;

        vm.prank(facilitator);
        escrow.deposit(escrowId1, buyer, merchant, 100e6, releaseTime);

        vm.warp(releaseTime);

        vm.prank(facilitator);
        escrow.release(escrowId1);

        assertTrue(escrow.getEscrow(escrowId1).status == ShulamEscrow.Status.Released);
    }

    // --- Refund ---

    function test_Refund_Success() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(facilitator);
        escrow.refund(escrowId1);

        ShulamEscrow.Escrow memory e = escrow.getEscrow(escrowId1);
        assertTrue(e.status == ShulamEscrow.Status.Refunded);
        assertEq(usdc.balanceOf(buyer), 100e6);
        assertEq(escrow.totalEscrowed(), 0);
    }

    function test_Refund_EmitsEvent() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.expectEmit(true, true, false, true);
        emit Refunded(escrowId1, buyer, 100e6);

        vm.prank(facilitator);
        escrow.refund(escrowId1);
    }

    function test_Refund_Unauthorized() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(random);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.refund(escrowId1);
    }

    function test_Refund_AfterRelease() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        vm.prank(facilitator);
        escrow.release(escrowId1);

        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowAlreadySettled.selector);
        escrow.refund(escrowId1);
    }

    // --- Multi-escrow ---

    function test_MultipleEscrows() public {
        _deposit(escrowId1, buyer, merchant, 100e6);

        address merchant2 = address(0xE);
        _deposit(escrowId2, buyer, merchant2, 200e6);

        assertEq(escrow.totalEscrowed(), 300e6);

        vm.prank(facilitator);
        escrow.release(escrowId1);

        vm.prank(facilitator);
        escrow.refund(escrowId2);

        assertEq(usdc.balanceOf(merchant), 100e6);
        assertEq(usdc.balanceOf(buyer), 200e6);
        assertEq(escrow.totalEscrowed(), 0);
    }

    function test_TotalEscrowed_AfterPartialRefund() public {
        _deposit(escrowId1, buyer, merchant, 100e6);
        _deposit(escrowId2, buyer, merchant, 200e6);

        assertEq(escrow.totalEscrowed(), 300e6);

        vm.prank(facilitator);
        escrow.refund(escrowId1);

        assertEq(escrow.totalEscrowed(), 200e6);
        assertEq(usdc.balanceOf(buyer), 100e6);
    }

    // --- setDisputeResolver ---

    function test_SetDisputeResolver() public {
        address resolver = address(0x123);
        vm.prank(facilitator);
        escrow.setDisputeResolver(resolver);
        assertEq(escrow.disputeResolver(), resolver);
    }

    function test_SetDisputeResolver_Unauthorized() public {
        vm.prank(random);
        vm.expectRevert(ShulamEscrow.Unauthorized.selector);
        escrow.setDisputeResolver(address(0x123));
    }

    function test_SetDisputeResolver_ZeroAddress() public {
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.InvalidAddress.selector);
        escrow.setDisputeResolver(address(0));
    }
}
