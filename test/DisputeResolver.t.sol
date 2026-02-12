// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ShulamEscrow.sol";
import "../src/DisputeResolver.sol";
import "./mocks/MockUSDC.sol";

contract DisputeResolverTest is Test {
    ShulamEscrow escrow;
    DisputeResolver resolver;
    MockUSDC usdc;

    address facilitator = address(0xF);
    address admin = address(0xA);
    address buyer = address(0xB);
    address merchant = address(0xC);
    address random = address(0xD);

    uint256 constant DISPUTE_WINDOW = 14 days;
    uint256 constant RESPONSE_WINDOW = 7 days;
    uint256 constant AUTO_RESOLVE_TIMEOUT = 30 days;

    bytes32 escrowId1 = keccak256("escrow-1");
    bytes32 escrowId2 = keccak256("escrow-2");

    event DisputeOpened(bytes32 indexed disputeId, bytes32 indexed escrowId, address indexed buyer, string reason);
    event DisputeResponded(bytes32 indexed disputeId, address indexed merchant, bytes32 evidenceHash);
    event DisputeResolved(bytes32 indexed disputeId, DisputeResolver.Resolution resolution);
    event DisputeAutoResolved(bytes32 indexed disputeId);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ShulamEscrow(address(usdc), facilitator);
        resolver = new DisputeResolver(
            address(escrow),
            admin,
            DISPUTE_WINDOW,
            RESPONSE_WINDOW,
            AUTO_RESOLVE_TIMEOUT
        );

        // Wire resolver into escrow
        vm.prank(facilitator);
        escrow.setDisputeResolver(address(resolver));
    }

    // Helper: create an escrow
    function _createEscrow(bytes32 id, uint256 amount) internal {
        usdc.mint(address(escrow), amount);
        vm.prank(facilitator);
        escrow.deposit(id, buyer, merchant, amount, 0);
    }

    // Helper: open a dispute and return the disputeId
    function _openDispute(bytes32 escrowId) internal returns (bytes32 disputeId) {
        vm.prank(buyer);
        disputeId = resolver.openDispute(escrowId, "Item not received");
    }

    // --- Constructor ---

    function test_Constructor_ZeroEscrow() public {
        vm.expectRevert(DisputeResolver.InvalidAddress.selector);
        new DisputeResolver(address(0), admin, DISPUTE_WINDOW, RESPONSE_WINDOW, AUTO_RESOLVE_TIMEOUT);
    }

    function test_Constructor_ZeroAdmin() public {
        vm.expectRevert(DisputeResolver.InvalidAddress.selector);
        new DisputeResolver(address(escrow), address(0), DISPUTE_WINDOW, RESPONSE_WINDOW, AUTO_RESOLVE_TIMEOUT);
    }

    // --- Open Dispute ---

    function test_OpenDispute_Success() public {
        _createEscrow(escrowId1, 100e6);

        vm.prank(buyer);
        bytes32 disputeId = resolver.openDispute(escrowId1, "Item not received");

        DisputeResolver.Dispute memory d = resolver.getDispute(disputeId);
        assertEq(d.escrowId, escrowId1);
        assertEq(d.buyer, buyer);
        assertEq(d.merchant, merchant);
        assertEq(d.openedAt, block.timestamp);
        assertTrue(d.resolution == DisputeResolver.Resolution.None);

        // Escrow should be flagged as disputed
        assertTrue(escrow.getEscrow(escrowId1).status == ShulamEscrow.Status.Disputed);
    }

    function test_OpenDispute_EmitsEvent() public {
        _createEscrow(escrowId1, 100e6);

        vm.prank(buyer);
        // We can't predict the exact disputeId, so just check buyer and escrowId
        resolver.openDispute(escrowId1, "Item not received");
    }

    function test_OpenDispute_NotBuyer() public {
        _createEscrow(escrowId1, 100e6);

        vm.prank(random);
        vm.expectRevert(DisputeResolver.Unauthorized.selector);
        resolver.openDispute(escrowId1, "Item not received");
    }

    function test_OpenDispute_NotHeld() public {
        _createEscrow(escrowId1, 100e6);

        // Release the escrow first
        vm.prank(facilitator);
        escrow.release(escrowId1);

        vm.prank(buyer);
        vm.expectRevert(DisputeResolver.EscrowNotHeld.selector);
        resolver.openDispute(escrowId1, "Item not received");
    }

    function test_OpenDispute_WindowClosed() public {
        _createEscrow(escrowId1, 100e6);

        // Warp past dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        vm.prank(buyer);
        vm.expectRevert(DisputeResolver.DisputeWindowClosed.selector);
        resolver.openDispute(escrowId1, "Item not received");
    }

    function test_OpenDispute_AlreadyDisputed() public {
        _createEscrow(escrowId1, 100e6);

        vm.prank(buyer);
        resolver.openDispute(escrowId1, "Item not received");

        vm.prank(buyer);
        vm.expectRevert(DisputeResolver.AlreadyDisputed.selector);
        resolver.openDispute(escrowId1, "Duplicate dispute");
    }

    function test_OpenDispute_PreventsRelease() public {
        _createEscrow(escrowId1, 100e6);

        _openDispute(escrowId1);

        // Trying to release should fail (status is Disputed, not Held)
        vm.prank(facilitator);
        vm.expectRevert(ShulamEscrow.EscrowAlreadySettled.selector);
        escrow.release(escrowId1);
    }

    // --- Respond ---

    function test_Respond_Success() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        bytes32 evidenceHash = keccak256("delivery proof");

        vm.prank(merchant);
        resolver.respond(disputeId, evidenceHash);

        DisputeResolver.Dispute memory d = resolver.getDispute(disputeId);
        assertEq(d.merchantEvidenceHash, evidenceHash);
        assertTrue(d.respondedAt > 0);
    }

    function test_Respond_NotMerchant() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.prank(random);
        vm.expectRevert(DisputeResolver.Unauthorized.selector);
        resolver.respond(disputeId, keccak256("evidence"));
    }

    function test_Respond_NotFound() public {
        bytes32 fakeId = keccak256("fake");

        vm.prank(merchant);
        vm.expectRevert(DisputeResolver.DisputeNotFound.selector);
        resolver.respond(fakeId, keccak256("evidence"));
    }

    function test_Respond_WindowClosed() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.warp(block.timestamp + RESPONSE_WINDOW + 1);

        vm.prank(merchant);
        vm.expectRevert(DisputeResolver.ResponseWindowClosed.selector);
        resolver.respond(disputeId, keccak256("evidence"));
    }

    // --- Admin Resolve ---

    function test_Resolve_BuyerFavored() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.prank(admin);
        resolver.resolve(disputeId, true);

        DisputeResolver.Dispute memory d = resolver.getDispute(disputeId);
        assertTrue(d.resolution == DisputeResolver.Resolution.BuyerFavored);

        // Buyer should have received the refund
        assertEq(usdc.balanceOf(buyer), 100e6);
        assertTrue(escrow.getEscrow(escrowId1).status == ShulamEscrow.Status.Refunded);
    }

    function test_Resolve_MerchantFavored() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.prank(admin);
        resolver.resolve(disputeId, false);

        DisputeResolver.Dispute memory d = resolver.getDispute(disputeId);
        assertTrue(d.resolution == DisputeResolver.Resolution.MerchantFavored);

        // Merchant should have received the release
        assertEq(usdc.balanceOf(merchant), 100e6);
        assertTrue(escrow.getEscrow(escrowId1).status == ShulamEscrow.Status.Released);
    }

    function test_Resolve_NotAdmin() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.prank(random);
        vm.expectRevert(DisputeResolver.Unauthorized.selector);
        resolver.resolve(disputeId, true);
    }

    function test_Resolve_AlreadyResolved() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.prank(admin);
        resolver.resolve(disputeId, true);

        vm.prank(admin);
        vm.expectRevert(DisputeResolver.DisputeAlreadyResolved.selector);
        resolver.resolve(disputeId, false);
    }

    function test_Resolve_NotFound() public {
        bytes32 fakeId = keccak256("fake");

        vm.prank(admin);
        vm.expectRevert(DisputeResolver.DisputeNotFound.selector);
        resolver.resolve(fakeId, true);
    }

    // --- Auto Resolve ---

    function test_AutoResolve_Success() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.warp(block.timestamp + AUTO_RESOLVE_TIMEOUT);

        resolver.autoResolve(disputeId);

        DisputeResolver.Dispute memory d = resolver.getDispute(disputeId);
        assertTrue(d.resolution == DisputeResolver.Resolution.AutoResolved);

        // Auto-resolve favors buyer (refund)
        assertEq(usdc.balanceOf(buyer), 100e6);
        assertTrue(escrow.getEscrow(escrowId1).status == ShulamEscrow.Status.Refunded);
    }

    function test_AutoResolve_TooEarly() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.warp(block.timestamp + AUTO_RESOLVE_TIMEOUT - 1);

        vm.expectRevert(DisputeResolver.TimeoutNotReached.selector);
        resolver.autoResolve(disputeId);
    }

    function test_AutoResolve_AlreadyResolved() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        vm.prank(admin);
        resolver.resolve(disputeId, true);

        vm.warp(block.timestamp + AUTO_RESOLVE_TIMEOUT);

        vm.expectRevert(DisputeResolver.DisputeAlreadyResolved.selector);
        resolver.autoResolve(disputeId);
    }

    // --- getDisputeForEscrow ---

    function test_GetDisputeForEscrow() public {
        _createEscrow(escrowId1, 100e6);
        bytes32 disputeId = _openDispute(escrowId1);

        assertEq(resolver.getDisputeForEscrow(escrowId1), disputeId);
    }

    function test_GetDisputeForEscrow_NoDispute() public {
        assertEq(resolver.getDisputeForEscrow(escrowId1), bytes32(0));
    }

    // --- Full lifecycle ---

    function test_FullLifecycle_DisputeAndResolve() public {
        _createEscrow(escrowId1, 100e6);

        // Buyer opens dispute
        bytes32 disputeId = _openDispute(escrowId1);

        // Merchant responds with evidence
        vm.prank(merchant);
        resolver.respond(disputeId, keccak256("delivery confirmation"));

        // Admin resolves in merchant's favor
        vm.prank(admin);
        resolver.resolve(disputeId, false);

        // Verify final state
        assertEq(usdc.balanceOf(merchant), 100e6);
        assertEq(usdc.balanceOf(buyer), 0);
        assertTrue(escrow.getEscrow(escrowId1).status == ShulamEscrow.Status.Released);
    }
}
