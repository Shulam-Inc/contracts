// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../src/ShulamEscrow.sol";
import "../../src/CashbackVault.sol";
import "../mocks/MockUSDC.sol";

// =============================================================
//                     ESCROW HANDLER
// =============================================================

/// @dev Handler contract that the invariant fuzzer calls into.
contract EscrowHandler is Test {
    ShulamEscrow public escrow;
    MockUSDC public usdc;
    address public facilitator;

    bytes32[] public escrowIds;
    uint256 public nextId;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalReleased;
    uint256 public ghost_totalRefunded;

    constructor(ShulamEscrow _escrow, MockUSDC _usdc, address _facilitator) {
        escrow = _escrow;
        usdc = _usdc;
        facilitator = _facilitator;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000e6);

        bytes32 id = keccak256(abi.encodePacked("inv", nextId));
        nextId++;

        usdc.mint(address(escrow), amount);

        vm.prank(facilitator);
        escrow.deposit(id, address(0xB), address(0xC), amount, 0);

        escrowIds.push(id);
        ghost_totalDeposited += amount;
    }

    function release(uint256 idIndex) external {
        if (escrowIds.length == 0) return;
        idIndex = bound(idIndex, 0, escrowIds.length - 1);
        bytes32 id = escrowIds[idIndex];

        ShulamEscrow.Escrow memory e = escrow.getEscrow(id);
        if (e.status != ShulamEscrow.Status.Held) return;

        vm.prank(facilitator);
        escrow.release(id);

        ghost_totalReleased += e.amount;
    }

    function refund(uint256 idIndex) external {
        if (escrowIds.length == 0) return;
        idIndex = bound(idIndex, 0, escrowIds.length - 1);
        bytes32 id = escrowIds[idIndex];

        ShulamEscrow.Escrow memory e = escrow.getEscrow(id);
        if (e.status != ShulamEscrow.Status.Held) return;

        vm.prank(facilitator);
        escrow.refund(id);

        ghost_totalRefunded += e.amount;
    }

    function getEscrowIdsLength() external view returns (uint256) {
        return escrowIds.length;
    }
}

// =============================================================
//                    ESCROW INVARIANT TESTS
// =============================================================

contract InvariantEscrowTest is StdInvariant, Test {
    ShulamEscrow escrow;
    MockUSDC usdc;
    EscrowHandler handler;

    address facilitator = address(0xF);

    function setUp() public {
        usdc = new MockUSDC();
        escrow = new ShulamEscrow(address(usdc), facilitator);
        handler = new EscrowHandler(escrow, usdc, facilitator);

        targetContract(address(handler));
    }

    /// @notice totalEscrowed must always equal USDC balance
    function invariant_TotalEscrowedMatchesBalance() public view {
        uint256 contractBalance = usdc.balanceOf(address(escrow));
        uint256 totalEscrowed = escrow.totalEscrowed();
        assertEq(
            contractBalance,
            totalEscrowed,
            "USDC balance must equal totalEscrowed"
        );
    }

    /// @notice totalEscrowed == deposits - releases - refunds (ghost variable check)
    function invariant_GhostAccountingMatches() public view {
        uint256 expected = handler.ghost_totalDeposited()
            - handler.ghost_totalReleased()
            - handler.ghost_totalRefunded();
        assertEq(
            escrow.totalEscrowed(),
            expected,
            "totalEscrowed must equal deposits - releases - refunds"
        );
    }

    /// @notice totalEscrowed must never exceed the contract's USDC balance
    function invariant_TotalEscrowedNeverExceedsBalance() public view {
        assertLe(
            escrow.totalEscrowed(),
            usdc.balanceOf(address(escrow)),
            "totalEscrowed must never exceed USDC balance"
        );
    }

    /// @notice Settled escrows retain their amount and cannot be modified
    function invariant_SettledEscrowsAreImmutable() public view {
        uint256 count = handler.getEscrowIdsLength();
        for (uint256 i = 0; i < count && i < 20; i++) {
            bytes32 id = handler.escrowIds(i);
            ShulamEscrow.Escrow memory e = escrow.getEscrow(id);
            if (e.status == ShulamEscrow.Status.Released || e.status == ShulamEscrow.Status.Refunded) {
                assertTrue(
                    e.amount > 0,
                    "Settled escrow must retain its amount"
                );
            }
        }
    }
}

// =============================================================
//                    CASHBACK HANDLER
// =============================================================

/// @dev Handler contract for CashbackVault invariant fuzzing.
contract CashbackHandler is Test {
    CashbackVault public vault;
    MockUSDC public usdc;
    address public facilitator;

    address[5] public buyers;
    uint256 public buyerCount;

    uint256 public ghost_totalCredited;
    uint256 public ghost_totalWithdrawn;

    constructor(CashbackVault _vault, MockUSDC _usdc, address _facilitator) {
        vault = _vault;
        usdc = _usdc;
        facilitator = _facilitator;

        buyers[0] = address(0xB0);
        buyers[1] = address(0xB1);
        buyers[2] = address(0xB2);
        buyers[3] = address(0xB3);
        buyers[4] = address(0xB4);
        buyerCount = 5;
    }

    function credit(uint256 amount, uint256 buyerSeed) external {
        amount = bound(amount, 1, 1_000_000e6);
        address buyer = buyers[buyerSeed % buyerCount];

        usdc.mint(address(vault), amount);

        vm.prank(facilitator);
        vault.credit(buyer, amount);

        ghost_totalCredited += amount;
    }

    function withdraw(uint256 buyerIndex, uint256 amount) external {
        buyerIndex = bound(buyerIndex, 0, buyerCount - 1);
        address buyer = buyers[buyerIndex];

        uint256 balance = vault.balanceOf(buyer);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(facilitator);
        vault.withdraw(buyer, amount);

        ghost_totalWithdrawn += amount;
    }

    function getBuyer(uint256 index) external view returns (address) {
        return buyers[index];
    }
}

// =============================================================
//                   CASHBACK INVARIANT TESTS
// =============================================================

contract InvariantCashbackTest is StdInvariant, Test {
    CashbackVault vault;
    MockUSDC usdc;
    CashbackHandler handler;

    address facilitator = address(0xF);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new CashbackVault(address(usdc), facilitator, 0); // no minimum for invariant tests
        handler = new CashbackHandler(vault, usdc, facilitator);

        targetContract(address(handler));
    }

    /// @notice totalAccrued must always equal USDC balance held by the vault
    function invariant_TotalAccruedMatchesBalance() public view {
        uint256 contractBalance = usdc.balanceOf(address(vault));
        uint256 totalAccrued = vault.totalAccrued();
        assertEq(
            totalAccrued,
            contractBalance,
            "totalAccrued must equal USDC balance"
        );
    }

    /// @notice totalAccrued == ghost_totalCredited - ghost_totalWithdrawn
    function invariant_GhostAccountingMatches() public view {
        uint256 expected = handler.ghost_totalCredited()
            - handler.ghost_totalWithdrawn();
        assertEq(
            vault.totalAccrued(),
            expected,
            "totalAccrued must equal credited - withdrawn"
        );
    }

    /// @notice totalAccrued must never exceed the contract's USDC balance
    function invariant_TotalAccruedNeverExceedsBalance() public view {
        assertLe(
            vault.totalAccrued(),
            usdc.balanceOf(address(vault)),
            "totalAccrued must never exceed USDC balance"
        );
    }

    /// @notice Sum of individual buyer balances must equal totalAccrued
    function invariant_IndividualBalancesSumToTotal() public view {
        uint256 sum = 0;
        for (uint256 i = 0; i < handler.buyerCount(); i++) {
            sum += vault.balanceOf(handler.getBuyer(i));
        }
        assertEq(
            sum,
            vault.totalAccrued(),
            "Sum of buyer balances must equal totalAccrued"
        );
    }
}
