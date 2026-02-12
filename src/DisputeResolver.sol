// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ShulamEscrow.sol";

/// @title DisputeResolver
/// @notice Handles payment disputes for Shulam escrows. Buyers can open disputes
///         within a configurable window, merchants respond, and an admin resolves.
///         If no resolution occurs within the timeout, disputes auto-resolve in favor of the buyer.
contract DisputeResolver {
    // --- Errors ---
    error Unauthorized();
    error InvalidAddress();
    error DisputeNotFound();
    error DisputeAlreadyResolved();
    error DisputeWindowClosed();
    error EscrowNotHeld();
    error AlreadyDisputed();
    error ResponseWindowClosed();
    error TimeoutNotReached();

    // --- Events ---
    event DisputeOpened(bytes32 indexed disputeId, bytes32 indexed escrowId, address indexed buyer, string reason);
    event DisputeResponded(bytes32 indexed disputeId, address indexed merchant, bytes32 evidenceHash);
    event DisputeResolved(bytes32 indexed disputeId, Resolution resolution);
    event DisputeAutoResolved(bytes32 indexed disputeId);

    enum Resolution {
        None,
        BuyerFavored,
        MerchantFavored,
        AutoResolved
    }

    struct Dispute {
        bytes32 escrowId;
        address buyer;
        address merchant;
        string reason;
        bytes32 merchantEvidenceHash;
        uint256 openedAt;
        uint256 respondedAt;
        Resolution resolution;
    }

    ShulamEscrow public immutable escrow;
    address public immutable admin;

    uint256 public disputeWindow; // seconds after escrow creation to open dispute
    uint256 public responseWindow; // seconds merchant has to respond
    uint256 public autoResolveTimeout; // seconds after open before auto-resolve

    mapping(bytes32 => Dispute) public disputes;
    mapping(bytes32 => bytes32) public escrowToDispute; // escrowId => disputeId

    uint256 private _disputeNonce;

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor(
        address _escrow,
        address _admin,
        uint256 _disputeWindow,
        uint256 _responseWindow,
        uint256 _autoResolveTimeout
    ) {
        if (_escrow == address(0) || _admin == address(0)) revert InvalidAddress();
        escrow = ShulamEscrow(_escrow);
        admin = _admin;
        disputeWindow = _disputeWindow;
        responseWindow = _responseWindow;
        autoResolveTimeout = _autoResolveTimeout;
    }

    /// @notice Open a dispute on an escrow. Only the buyer of that escrow can call.
    function openDispute(bytes32 escrowId, string calldata reason) external returns (bytes32 disputeId) {
        ShulamEscrow.Escrow memory e = escrow.getEscrow(escrowId);

        if (msg.sender != e.buyer) revert Unauthorized();
        if (escrowToDispute[escrowId] != bytes32(0)) revert AlreadyDisputed();
        if (e.status != ShulamEscrow.Status.Held) revert EscrowNotHeld();
        if (block.timestamp > e.createdAt + disputeWindow) revert DisputeWindowClosed();

        disputeId = keccak256(abi.encodePacked("dispute", _disputeNonce));
        _disputeNonce++;

        disputes[disputeId] = Dispute({
            escrowId: escrowId,
            buyer: e.buyer,
            merchant: e.merchant,
            reason: reason,
            merchantEvidenceHash: bytes32(0),
            openedAt: block.timestamp,
            respondedAt: 0,
            resolution: Resolution.None
        });
        escrowToDispute[escrowId] = disputeId;

        // Flag the escrow as disputed to prevent release
        escrow.flagDispute(escrowId);

        emit DisputeOpened(disputeId, escrowId, e.buyer, reason);
    }

    /// @notice Merchant responds to a dispute with evidence.
    function respond(bytes32 disputeId, bytes32 evidenceHash) external {
        Dispute storage d = disputes[disputeId];
        if (d.openedAt == 0) revert DisputeNotFound();
        if (d.resolution != Resolution.None) revert DisputeAlreadyResolved();
        if (msg.sender != d.merchant) revert Unauthorized();
        if (block.timestamp > d.openedAt + responseWindow) revert ResponseWindowClosed();

        d.merchantEvidenceHash = evidenceHash;
        d.respondedAt = block.timestamp;

        emit DisputeResponded(disputeId, d.merchant, evidenceHash);
    }

    /// @notice Admin resolves a dispute in favor of buyer or merchant.
    function resolve(bytes32 disputeId, bool favorBuyer) external onlyAdmin {
        Dispute storage d = disputes[disputeId];
        if (d.openedAt == 0) revert DisputeNotFound();
        if (d.resolution != Resolution.None) revert DisputeAlreadyResolved();

        if (favorBuyer) {
            d.resolution = Resolution.BuyerFavored;
            escrow.refundDisputed(d.escrowId);
        } else {
            d.resolution = Resolution.MerchantFavored;
            escrow.releaseDisputed(d.escrowId);
        }

        emit DisputeResolved(disputeId, d.resolution);
    }

    /// @notice Auto-resolve a dispute after the timeout. Anyone can call.
    /// Defaults to buyer-favored (refund) as specified in PLAN.md.
    function autoResolve(bytes32 disputeId) external {
        Dispute storage d = disputes[disputeId];
        if (d.openedAt == 0) revert DisputeNotFound();
        if (d.resolution != Resolution.None) revert DisputeAlreadyResolved();
        if (block.timestamp < d.openedAt + autoResolveTimeout) revert TimeoutNotReached();

        d.resolution = Resolution.AutoResolved;
        escrow.refundDisputed(d.escrowId);

        emit DisputeAutoResolved(disputeId);
    }

    /// @notice View a dispute record.
    function getDispute(bytes32 disputeId) external view returns (Dispute memory) {
        return disputes[disputeId];
    }

    /// @notice Get the dispute ID for an escrow.
    function getDisputeForEscrow(bytes32 escrowId) external view returns (bytes32) {
        return escrowToDispute[escrowId];
    }
}
