// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Veera} from "../src/Veera.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployVeera is Script {
    function run() external returns (Veera, HelperConfig) {
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

        // 2. Validate CREATE2 deployer/factory address and codehash
        address expectedFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        require(manifest.factory == expectedFactory, "Unsupported CREATE2 factory address");

        uint256 codeSize;
        bytes32 codeHash;
        address fact = manifest.factory;
        assembly {
            codeSize := extcodesize(fact)
            codeHash := extcodehash(fact)
        }
        require(codeSize > 0, "CREATE2 factory not deployed on target chain");
        require(codeHash == manifest.factoryCodeHash, "Unexpected CREATE2 factory bytecode");

        // Validate targetAdmin contract (Gnosis Safe) exists on live networks
        if (block.chainid != 31337) {
            uint256 adminCodeSize;
            address targetAdminAddress = manifest.targetAdmin;
            assembly {
                adminCodeSize := extcodesize(targetAdminAddress)
            }
            require(adminCodeSize > 0, "Target admin must be a deployed contract/multisig");
        }

        // 3. Compute and validate predicted CREATE2 address
        bytes memory creationCode = abi.encodePacked(
            type(Veera).creationCode,
            abi.encode(
                manifest.name, manifest.symbol, manifest.bootstrapAdmin, manifest.constructorSupply, manifest.maxSupply
            )
        );
        bytes32 initCodeHash = keccak256(creationCode);
        address predicted = computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);

        console.log("--------------------------------------------------");
        console.log("Predicted address: ", predicted);
        console.log("Expected address:  ", manifest.expectedTokenAddress);
        console.log("--------------------------------------------------");

        if (block.chainid == 31337 && manifest.expectedTokenAddress == address(0)) {
            console.log("WARNING: expectedTokenAddress is zero. Bootstrapping mode active on local anvil.");
        } else {
            require(manifest.expectedTokenAddress != address(0), "expectedTokenAddress must be set on public chains");
            require(predicted == manifest.expectedTokenAddress, "Predicted address mismatch");
        }

        // Pre-deploy check: verify that the token has not been deployed already
        uint256 predictedCodeSize;
        assembly {
            predictedCodeSize := extcodesize(predicted)
        }
        require(predictedCodeSize == 0, "Contract already deployed at predicted address");

        // Start broadcast using the determined deployer signer path
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
        address deployedAddress = abi.decode(abi.encodePacked(bytes12(0), returnedData), (address));
        require(deployedAddress == predicted, "Deployed address mismatch");
        Veera token = Veera(deployedAddress);

        // 5. Mint initial supply post-deployment only on home chain (when expectedPostDeploymentSupply > 0)
        if (manifest.expectedPostDeploymentSupply > 0) {
            console.log("Minting initial supply to:", manifest.initialMintRecipient);
            token.mint(manifest.initialMintRecipient, manifest.expectedPostDeploymentSupply);
        }

        // 6. Post-deployment Role Setup
        console.log("Configuring target roles...");
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), manifest.targetAdmin);

        // Revoke roles from temporary bootstrap admin
        console.log("Revoking roles from bootstrap admin EOA...");
        token.revokeRole(token.MINTER_ROLE(), manifest.bootstrapAdmin);
        token.revokeRole(token.PAUSER_ROLE(), manifest.bootstrapAdmin);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), manifest.bootstrapAdmin);

        if (isTest) {
            vm.stopPrank();
        } else {
            vm.stopBroadcast();
        }

        // 7. Make role and supply handoff fail-closed
        console.log("Verifying final deployment state...");

        // Supply assertions
        require(token.totalSupply() == manifest.expectedPostDeploymentSupply, "Fail-closed: Total supply mismatch");
        if (manifest.expectedPostDeploymentSupply == 0) {
            require(token.totalSupply() == 0, "Fail-closed: Remote chain must start with zero supply");
        }

        // Bootstrap admin role revoking assertions
        require(
            !token.hasRole(token.DEFAULT_ADMIN_ROLE(), manifest.bootstrapAdmin),
            "Fail-closed: Bootstrap admin still has DEFAULT_ADMIN_ROLE"
        );
        require(
            !token.hasRole(token.MINTER_ROLE(), manifest.bootstrapAdmin),
            "Fail-closed: Bootstrap admin still has MINTER_ROLE"
        );
        require(
            !token.hasRole(token.PAUSER_ROLE(), manifest.bootstrapAdmin),
            "Fail-closed: Bootstrap admin still has PAUSER_ROLE"
        );

        // Target role assignment assertions
        require(
            token.hasRole(token.DEFAULT_ADMIN_ROLE(), manifest.targetAdmin),
            "Fail-closed: Target admin does not have DEFAULT_ADMIN_ROLE"
        );
        // Assert that pauser and minter roles are initially unassigned
        require(
            !token.hasRole(token.PAUSER_ROLE(), manifest.targetAdmin),
            "Fail-closed: Target admin should not have PAUSER_ROLE"
        );
        require(
            !token.hasRole(token.MINTER_ROLE(), manifest.targetAdmin),
            "Fail-closed: Target admin should not have MINTER_ROLE"
        );

        console.log("--------------------------------------------------");
        console.log("DEPLOYMENT COMPLETE & VERIFIED");
        console.log("Chain ID:     ", block.chainid);
        console.log("Token Address:", address(token));
        console.log("Total Supply: ", token.totalSupply());
        console.log("--------------------------------------------------");

        return (token, config);
    }
}
