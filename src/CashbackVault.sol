// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC20.sol";

/// @title CashbackVault
/// @notice Manages cashback credits for Shulam buyers. Facilitator credits cashback
///         on settlement, buyers can withdraw accumulated cashback.
contract CashbackVault {
    // --- Errors ---
    error Unauthorized();
    error InvalidAmount();
    error InvalidAddress();
    error InsufficientBalance();
    error BelowMinimumClaim();
    error TransferFailed();

    // --- Events ---
    event Credited(address indexed buyer, uint256 amount);
    event Withdrawn(address indexed buyer, uint256 amount);
    event MinimumClaimUpdated(uint256 oldAmount, uint256 newAmount);

    IERC20 public immutable usdc;
    address public immutable facilitator;

    mapping(address => uint256) public balances;
    uint256 public totalAccrued;
    uint256 public minimumClaim;

    modifier onlyFacilitator() {
        if (msg.sender != facilitator) revert Unauthorized();
        _;
    }

    constructor(address _usdc, address _facilitator, uint256 _minimumClaim) {
        if (_usdc == address(0)) revert InvalidAddress();
        if (_facilitator == address(0)) revert InvalidAddress();
        usdc = IERC20(_usdc);
        facilitator = _facilitator;
        minimumClaim = _minimumClaim;
    }

    /// @notice Set the minimum claim threshold. Only facilitator can call.
    function setMinimumClaim(uint256 _minimumClaim) external onlyFacilitator {
        uint256 old = minimumClaim;
        minimumClaim = _minimumClaim;
        emit MinimumClaimUpdated(old, _minimumClaim);
    }

    /// @notice Credit cashback to a buyer. Only the facilitator can call.
    /// The vault must already hold enough USDC to cover the credit.
    function credit(address buyer, uint256 amount) external onlyFacilitator {
        if (amount == 0) revert InvalidAmount();
        if (buyer == address(0)) revert InvalidAddress();
        if (usdc.balanceOf(address(this)) < totalAccrued + amount) revert InsufficientBalance();

        balances[buyer] += amount;
        totalAccrued += amount;

        emit Credited(buyer, amount);
    }

    /// @notice Withdraw cashback. Callable by the buyer or the facilitator.
    function withdraw(address buyer, uint256 amount) external {
        if (msg.sender != buyer && msg.sender != facilitator) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        if (balances[buyer] < amount) revert InsufficientBalance();
        if (amount < minimumClaim) revert BelowMinimumClaim();

        balances[buyer] -= amount;
        totalAccrued -= amount;

        emit Withdrawn(buyer, amount);

        if (!usdc.transfer(buyer, amount)) revert TransferFailed();
    }

    /// @notice View a buyer's cashback balance.
    function balanceOf(address buyer) external view returns (uint256) {
        return balances[buyer];
    }
}
