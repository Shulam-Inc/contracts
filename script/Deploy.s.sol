// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ShulamEscrow.sol";
import "../src/CashbackVault.sol";
import "../src/DisputeResolver.sol";

contract Deploy is Script {
    // USDC on Base Sepolia
    address constant USDC_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    // USDC on Base Mainnet
    address constant USDC_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Default dispute parameters
    uint256 constant DISPUTE_WINDOW = 14 days;
    uint256 constant RESPONSE_WINDOW = 7 days;
    uint256 constant AUTO_RESOLVE_TIMEOUT = 30 days;
    uint256 constant MINIMUM_CLAIM = 1e6; // 1 USDC

    function run() external {
        address facilitator = vm.envAddress("FACILITATOR_WALLET_ADDRESS");
        address admin = vm.envOr("ADMIN_ADDRESS", facilitator);
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        bool isMainnet = vm.envOr("MAINNET", false);

        address usdc = isMainnet ? USDC_MAINNET : USDC_SEPOLIA;

        vm.startBroadcast(deployerKey);

        ShulamEscrow escrowContract = new ShulamEscrow(usdc, facilitator);
        CashbackVault vault = new CashbackVault(usdc, facilitator, MINIMUM_CLAIM);
        DisputeResolver resolver = new DisputeResolver(
            address(escrowContract),
            admin,
            DISPUTE_WINDOW,
            RESPONSE_WINDOW,
            AUTO_RESOLVE_TIMEOUT
        );

        // Wire the dispute resolver into the escrow contract
        escrowContract.setDisputeResolver(address(resolver));

        vm.stopBroadcast();

        console.log("=== Deployment Summary ===");
        console.log("Network:", isMainnet ? "Base Mainnet" : "Base Sepolia");
        console.log("ShulamEscrow:", address(escrowContract));
        console.log("CashbackVault:", address(vault));
        console.log("DisputeResolver:", address(resolver));
        console.log("Facilitator:", facilitator);
        console.log("Admin:", admin);
        console.log("USDC:", usdc);
    }
}
