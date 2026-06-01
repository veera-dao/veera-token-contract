// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Veera} from "../src/Veera.sol";
import {
    HelperConfig,
    BASE_MAINNET_CHAINID,
    BASE_TESTNET_CHAINID,
    BSC_MAINNET_CHAINID,
    BSC_TESTNET_CHAINID,
    LOCAL_CHAINID
} from "./HelperConfig.s.sol";

contract DeployVeera is Script {
    // Salt used for deterministic deployments across chains
    bytes32 public constant VEERA_SALT = keccak256("VeeraTokenSalt.v1");

    function run() external returns (Veera, HelperConfig) {
        HelperConfig config = new HelperConfig();

        // Get deterministic constructor arguments (same on all chains of the same network type)
        (
            string memory name,
            string memory symbol,
            address constructorAdmin,
            uint256 constructorSupply,
            uint256 maxSupply
        ) = config.getDeterministicConstructorArgs(tx.origin);

        // Get the target/final network configuration
        (address targetAdmin, uint256 targetSupply,,,) = config.activeNetworkConfig();

        require(constructorAdmin != address(0), "Error: Constructor Admin Address cannot be zero");
        require(targetAdmin != address(0), "Error: Target Admin Address cannot be zero");
        require(bytes(name).length > 0, "Error: Token name cannot be empty");
        require(bytes(symbol).length > 0, "Error: Token symbol cannot be empty");
        require(maxSupply > 0, "Error: Max supply must be greater than zero");
        require(constructorSupply <= maxSupply, "Error: Constructor supply exceeds max supply");

        // Log chain ID and parameters for verification
        console.log("--------------------------------------------------");
        console.log("Preparing deployment to Chain ID:", block.chainid);
        console.log("Constructor Admin:", constructorAdmin);
        console.log("Target Admin:     ", targetAdmin);
        console.log("Max Supply:       ", maxSupply);
        console.log("--------------------------------------------------");

        require(
            block.chainid == BASE_MAINNET_CHAINID || block.chainid == BASE_TESTNET_CHAINID
                || block.chainid == BSC_MAINNET_CHAINID || block.chainid == BSC_TESTNET_CHAINID
                || block.chainid == LOCAL_CHAINID,
            "Error: Unsupported chain ID. Verify RPC URL is correct!"
        );

        // Validate target admin address for live networks
        if (
            block.chainid == BASE_MAINNET_CHAINID || block.chainid == BASE_TESTNET_CHAINID
                || block.chainid == BSC_MAINNET_CHAINID || block.chainid == BSC_TESTNET_CHAINID
        ) {
            // Check that target admin is a contract (e.g. Gnosis Safe) on mainnets
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(targetAdmin)
            }
            if (block.chainid == BASE_MAINNET_CHAINID || block.chainid == BSC_MAINNET_CHAINID) {
                require(codeSize > 0, "Error: Target admin must be a contract (i.e. a Gnosis Safe)");
            } else if (codeSize == 0) {
                console.log("WARNING: Target admin is not a contract (i.e. Gnosis Safe)");
            }
        }

        vm.startBroadcast();

        // Deploy using CREATE2 for deterministic addressing
        Veera token = new Veera{salt: VEERA_SALT}(
            name,
            symbol,
            constructorAdmin,
            constructorSupply, // Deploy with 0 initial supply
            maxSupply
        );

        // Post-deployment Supply Minting: Mint initial supply on home chain (Base)
        if (targetSupply > 0) {
            if (token.hasRole(token.MINTER_ROLE(), tx.origin)) {
                console.log("Broadcaster is minter. Minting initial supply to target admin:", targetSupply);
                token.mint(targetAdmin, targetSupply);
            } else {
                console.log("--------------------------------------------------");
                console.log("WARNING: Broadcaster does not have MINTER_ROLE.");
                console.log("Initial supply must be minted manually by target admin.");
                console.log("--------------------------------------------------");
            }
        }

        // Post-deployment Role Setup: Transfer roles to target admin if they differ
        if (targetAdmin != constructorAdmin) {
            console.log("Configuring target admin roles...");

            // Grant roles to target admin
            token.grantRole(token.DEFAULT_ADMIN_ROLE(), targetAdmin);
            token.grantRole(token.MINTER_ROLE(), targetAdmin);
            token.grantRole(token.PAUSER_ROLE(), targetAdmin);

            // Revoke roles from temporary constructor admin
            token.revokeRole(token.MINTER_ROLE(), constructorAdmin);
            token.revokeRole(token.PAUSER_ROLE(), constructorAdmin);
            token.revokeRole(token.DEFAULT_ADMIN_ROLE(), constructorAdmin);
        }

        vm.stopBroadcast();

        console.log("--------------------------------------------------");
        console.log("DEPLOYMENT COMPLETE");
        console.log("Chain ID:     ", block.chainid);
        console.log("Token Address:", address(token));
        console.log("Target Admin: ", targetAdmin);
        console.log("Total Supply: ", token.totalSupply());
        console.log("--------------------------------------------------");

        return (token, config);
    }
}
