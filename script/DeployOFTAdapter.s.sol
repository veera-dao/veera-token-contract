// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployOFTAdapter
 * @notice Script to deploy the VeeraMintBurnOFTAdapter contract using CREATE2.
 *
 * @dev Separate Lifecycle Phases:
 * 1. Deployment: Deploying the contract using this script.
 * 2. Configuration: Setting peers (e.g. via ConfigureOFTAdapter.s.sol).
 * 3. Activation: Token Admin/Safe granting MINTER_ROLE to the adapter on the token contract.
 * These are separate operational phases handled by distinct tasks/transactions.
 *
 * @dev Deterministic Address Invariant:
 * The bridge adapter address will only match across chains when token address, LayerZero endpoint,
 * targetAdmin, salt, factory, bytecode, and compiler settings all match.
 */
contract DeployOFTAdapter is Script {
    function run() external returns (VeeraMintBurnOFTAdapter, HelperConfig) {
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        // 1. Determine deployer address (defaulting to manifest.bootstrapAdmin if env is not set)
        bool isTest = msg.sender.code.length > 0;
        address deployerAddress;
        if (isTest) {
            deployerAddress = manifest.bootstrapAdmin;
        } else {
            deployerAddress = vm.envOr("DEPLOYER_ADDRESS", manifest.bootstrapAdmin);
            require(deployerAddress == manifest.bootstrapAdmin, "Wrong deployer address in environment");
        }

        // 2. Validate CREATE2 deployer/factory bytecode
        uint256 codeSize;
        bytes32 codeHash;
        address fact = manifest.factory;
        assembly {
            codeSize := extcodesize(fact)
            codeHash := extcodehash(fact)
        }
        require(codeSize > 0, "CREATE2 factory not deployed on target chain");
        require(codeHash == manifest.factoryCodeHash, "Unexpected CREATE2 factory bytecode");

        // Validate token contract exists
        if (block.chainid != 31337) {
            uint256 tokenCodeSize;
            address tokenAddress = manifest.expectedTokenAddress;
            assembly {
                tokenCodeSize := extcodesize(tokenAddress)
            }
            require(tokenCodeSize > 0, "Veera token contract must be deployed before adapter");
        }

        // Validate lzEndpoint exists on live networks
        if (block.chainid != 31337) {
            require(manifest.lzEndpoint != address(0), "LayerZero endpoint cannot be zero address");
            uint256 lzCodeSize;
            address lz = manifest.lzEndpoint;
            assembly {
                lzCodeSize := extcodesize(lz)
            }
            require(lzCodeSize > 0, "LayerZero endpoint must be a deployed contract");
        } else {
            // Local Anvil: if endpoint is zero, print warning
            if (manifest.lzEndpoint == address(0)) {
                console.log("WARNING: LayerZero endpoint is zero address (Anvil mode)");
            }
        }

        // 3. Compute and validate predicted CREATE2 address
        bytes memory creationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        address predicted = vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);

        console.log("--------------------------------------------------");
        console.log("Init code hash:    ");
        console.logBytes32(initCodeHash);
        console.log("Predicted address: ", predicted);
        console.log("Expected address:  ", manifest.expectedBridgeAddress);
        console.log("--------------------------------------------------");

        if (block.chainid == 31337 && manifest.expectedBridgeAddress == address(0)) {
            console.log("WARNING: expectedBridgeAddress is zero. Bootstrapping mode active on local anvil.");
        } else {
            require(manifest.expectedBridgeAddress != address(0), "expectedBridgeAddress must be set on public chains");
            require(predicted == manifest.expectedBridgeAddress, "Predicted bridge address mismatch");
        }

        // Dry-run mode check
        bool dryRun = vm.envOr("DRY_RUN", false);
        if (dryRun) {
            console.log("------------------ DRY RUN ACTIVE ----------------");
            console.log("Would deploy VeeraMintBurnOFTAdapter to predicted address: ", predicted);
            console.log("Salt:                                                    ", vm.toString(manifest.salt));
            console.log("Token:                                                   ", manifest.expectedTokenAddress);
            console.log("Endpoint:                                                ", manifest.lzEndpoint);
            console.log("Delegate/Admin:                                          ", manifest.targetAdmin);
            console.log("--------------------------------------------------");
            return (VeeraMintBurnOFTAdapter(predicted), config);
        }

        // Pre-deploy check: verify if already deployed
        uint256 predictedCodeSize;
        assembly {
            predictedCodeSize := extcodesize(predicted)
        }

        VeeraMintBurnOFTAdapter adapter;
        if (predictedCodeSize > 0) {
            console.log("WARNING: Contract already deployed at predicted address:", predicted);
            console.log("WARNING: Running in VERIFICATION-ONLY mode. No transactions will be broadcast.");
            adapter = VeeraMintBurnOFTAdapter(predicted);
        } else {
            // Start broadcast
            if (isTest) {
                vm.startPrank(deployerAddress);
            } else {
                uint256 privateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
                if (privateKey != 0) {
                    address derived = vm.addr(privateKey);
                    require(derived == manifest.bootstrapAdmin, "Private key does not match bootstrapAdmin EOA");
                    vm.startBroadcast(privateKey);
                } else {
                    vm.startBroadcast(deployerAddress);
                }
            }

            // 4. Deploy using CREATE2 for deterministic addressing via the factory
            bytes memory deployData = abi.encodePacked(manifest.salt, creationCode);
            (bool success, bytes memory returnedData) = manifest.factory.call(deployData);
            require(success, "Failed to deploy via CREATE2 factory");
            require(returnedData.length == 20, "Unexpected CREATE2 factory return data length");
            address deployedAddress;
            assembly {
                deployedAddress := shr(96, mload(add(returnedData, 0x20)))
            }
            require(deployedAddress == predicted, "Deployed address mismatch");
            adapter = VeeraMintBurnOFTAdapter(deployedAddress);

            if (isTest) {
                vm.stopPrank();
            } else {
                vm.stopBroadcast();
            }
        }

        // 5. Post-deployment state assertions (fail-closed)
        console.log("Verifying final bridge deployment state...");
        require(address(adapter.token()) == manifest.expectedTokenAddress, "Fail-closed: Token address mismatch");
        require(adapter.owner() == manifest.targetAdmin, "Fail-closed: Owner/Delegate address mismatch");

        console.log("--------------------------------------------------");
        console.log("OFT ADAPTER DEPLOYMENT COMPLETE & VERIFIED");
        console.log("Chain ID:        ", block.chainid);
        console.log("Adapter Address: ", address(adapter));
        console.log("--------------------------------------------------");

        return (adapter, config);
    }
}
