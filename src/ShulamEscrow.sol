// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC20.sol";

/// @title ShulamEscrow
/// @notice Holds USDC in escrow for Shulam payments. Supports deposit, release, and refund
///         with time-locked releases and dispute integration.
contract ShulamEscrow {
    // --- Errors ---
    error Unauthorized();
    error EscrowNotFound();
    error EscrowAlreadySettled();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidAddress();
    error TransferFailed();
    error ReleaseTooEarly();
    error EscrowDisputed();

    // --- Events ---
    event Deposited(bytes32 indexed escrowId, address indexed buyer, address indexed merchant, uint256 amount);
    event Released(bytes32 indexed escrowId, address indexed merchant, uint256 amount);
    event Refunded(bytes32 indexed escrowId, address indexed buyer, uint256 amount);
    event DisputeFlagged(bytes32 indexed escrowId);

    enum Status {
        None,
        Held,
        Released,
        Refunded,
        Disputed
    }

    struct Escrow {
        address buyer;
        address merchant;
        uint256 amount;
        uint256 createdAt;
        uint256 releaseTime;
        Status status;
    }

    IERC20 public immutable usdc;
    address public immutable facilitator;
    address public disputeResolver;

    mapping(bytes32 => Escrow) public escrows;
    uint256 public totalEscrowed;

    modifier onlyFacilitator() {
        if (msg.sender != facilitator) revert Unauthorized();
        _;
    }

    modifier onlyDisputeResolver() {
        if (msg.sender != disputeResolver) revert Unauthorized();
        _;
    }

    constructor(address _usdc, address _facilitator) {
        if (_usdc == address(0)) revert InvalidAddress();
        if (_facilitator == address(0)) revert InvalidAddress();
        usdc = IERC20(_usdc);
        facilitator = _facilitator;
    }

    /// @notice Set the dispute resolver contract address. Only facilitator can set this.
    function setDisputeResolver(address _disputeResolver) external onlyFacilitator {
        if (_disputeResolver == address(0)) revert InvalidAddress();
        disputeResolver = _disputeResolver;
    }

    /// @notice Deposit USDC into escrow. The contract must already hold sufficient USDC.
    function deposit(
        bytes32 escrowId,
        address buyer,
        address merchant,
        uint256 amount,
        uint256 releaseTime
    ) external onlyFacilitator {
        if (amount == 0) revert InvalidAmount();
        if (buyer == address(0) || merchant == address(0)) revert InvalidAddress();
        if (buyer == merchant) revert InvalidAddress();
        if (escrows[escrowId].status != Status.None) revert EscrowAlreadySettled();
        if (usdc.balanceOf(address(this)) < totalEscrowed + amount) revert InsufficientBalance();

        escrows[escrowId] = Escrow({
            buyer: buyer,
            merchant: merchant,
            amount: amount,
            createdAt: block.timestamp,
            releaseTime: releaseTime,
            status: Status.Held
        });
        totalEscrowed += amount;

        emit Deposited(escrowId, buyer, merchant, amount);
    }

    /// @notice Release escrowed funds to the merchant. Callable by facilitator or merchant.
    function release(bytes32 escrowId) external {
        Escrow storage e = escrows[escrowId];
        if (e.status == Status.None) revert EscrowNotFound();
        if (e.status != Status.Held) revert EscrowAlreadySettled();
        if (e.status == Status.Disputed) revert EscrowDisputed();
        if (msg.sender != facilitator && msg.sender != e.merchant) revert Unauthorized();
        if (block.timestamp < e.releaseTime) revert ReleaseTooEarly();

        e.status = Status.Released;
        totalEscrowed -= e.amount;

        emit Released(escrowId, e.merchant, e.amount);

        if (!usdc.transfer(e.merchant, e.amount)) revert TransferFailed();
    }

    /// @notice Refund escrowed funds to the buyer. Only facilitator can call.
    function refund(bytes32 escrowId) external onlyFacilitator {
        Escrow storage e = escrows[escrowId];
        if (e.status == Status.None) revert EscrowNotFound();
        if (e.status != Status.Held && e.status != Status.Disputed) revert EscrowAlreadySettled();

        e.status = Status.Refunded;
        totalEscrowed -= e.amount;

        emit Refunded(escrowId, e.buyer, e.amount);

        if (!usdc.transfer(e.buyer, e.amount)) revert TransferFailed();
    }

    /// @notice Flag an escrow as disputed. Only the dispute resolver contract can call.
    function flagDispute(bytes32 escrowId) external onlyDisputeResolver {
        Escrow storage e = escrows[escrowId];
        if (e.status == Status.None) revert EscrowNotFound();
        if (e.status != Status.Held) revert EscrowAlreadySettled();

        e.status = Status.Disputed;
        emit DisputeFlagged(escrowId);
    }

    /// @notice Release disputed escrow to merchant. Only the dispute resolver can call.
    function releaseDisputed(bytes32 escrowId) external onlyDisputeResolver {
        Escrow storage e = escrows[escrowId];
        if (e.status != Status.Disputed) revert EscrowAlreadySettled();

        e.status = Status.Released;
        totalEscrowed -= e.amount;

        emit Released(escrowId, e.merchant, e.amount);

        if (!usdc.transfer(e.merchant, e.amount)) revert TransferFailed();
    }

    /// @notice Refund disputed escrow to buyer. Only the dispute resolver can call.
    function refundDisputed(bytes32 escrowId) external onlyDisputeResolver {
        Escrow storage e = escrows[escrowId];
        if (e.status != Status.Disputed) revert EscrowAlreadySettled();

        e.status = Status.Refunded;
        totalEscrowed -= e.amount;

        emit Refunded(escrowId, e.buyer, e.amount);

        if (!usdc.transfer(e.buyer, e.amount)) revert TransferFailed();
    }

    /// @notice View an escrow record.
    function getEscrow(bytes32 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }
}
