// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Veera} from "../src/Veera.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployVeera is Script {
    function run() external returns (Veera, HelperConfig) {
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        // 1. Validate broadcaster EOA (tx.origin is verified at runtime)
        if (msg.sender.code.length == 0) {
            require(tx.origin == manifest.bootstrapAdmin, "Broadcaster must be the bootstrap admin EOA");
        }

        // 2. Validate CREATE2 deployer/factory address
        // The default factory address used by Forge for deterministic deployments
        address expectedFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        require(manifest.factory == expectedFactory, "Unsupported CREATE2 factory address");

        uint256 codeSize;
        address fact = manifest.factory;
        assembly {
            codeSize := extcodesize(fact)
        }
        require(codeSize > 0, "CREATE2 factory not deployed on target chain");

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

        if (manifest.expectedTokenAddress == address(0)) {
            console.log("WARNING: expectedTokenAddress is zero. Bootstrapping mode active.");
        } else {
            require(predicted == manifest.expectedTokenAddress, "Predicted address does not match expectedTokenAddress");
        }

        // Start broadcast explicitly using the bootstrapAdmin EOA
        vm.startBroadcast(manifest.bootstrapAdmin);

        // 4. Deploy using CREATE2 for deterministic addressing
        Veera token = new Veera{salt: manifest.salt}(
            manifest.name, manifest.symbol, manifest.bootstrapAdmin, manifest.constructorSupply, manifest.maxSupply
        );

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

        vm.stopBroadcast();

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
