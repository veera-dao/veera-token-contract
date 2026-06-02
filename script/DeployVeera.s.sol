// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Veera} from "../src/Veera.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployVeera is Script {
    /// @dev keccak256 of the ABI-encoded global deterministic manifest parameters.
    ///      Recompute via `forge test --match-test test_logManifestIntegrityHash -vvv` after any manifest change.
    bytes32 constant EXPECTED_MANIFEST_INTEGRITY_HASH =
        0x311293f824025683a250cb4e44e77b038d0013d8e23027c586246f3ed612426c;

    function run() external returns (Veera, HelperConfig) {
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        // 1. Determine deployer address (defaulting to manifest.bootstrapAdmin if env is not set)
        // Heuristic: In Forge tests, msg.sender is the test contract (has code).
        // In live broadcasts, msg.sender is an EOA (no code).
        bool isTest = msg.sender.code.length > 0;
        address deployerAddress;
        if (isTest) {
            deployerAddress = manifest.bootstrapAdmin;
        } else {
            deployerAddress = vm.envOr("DEPLOYER_ADDRESS", manifest.bootstrapAdmin);
            require(deployerAddress == manifest.bootstrapAdmin, "Wrong deployer address in environment");
        }

        // Validate manifest integrity (skip check on local anvil if bootstrapping mode is active)
        if (block.chainid != 31337 || manifest.expectedTokenAddress != address(0)) {
            bytes32 calculatedHash = keccak256(
                abi.encode(
                    manifest.salt,
                    manifest.factory,
                    manifest.factoryCodeHash,
                    manifest.bootstrapAdmin,
                    keccak256(bytes(manifest.name)),
                    keccak256(bytes(manifest.symbol)),
                    manifest.constructorSupply,
                    manifest.maxSupply,
                    manifest.expectedTokenAddress
                )
            );
            require(
                calculatedHash == EXPECTED_MANIFEST_INTEGRITY_HASH,
                "DeployVeera: Manifest integrity hash mismatch. Global parameters differ from approved values."
            );
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
        bytes memory bytecode;
        string memory artifactPath = vm.envOr("ARTIFACT_PATH", string(""));

        if (bytes(artifactPath).length > 0) {
            bytecode = vm.getCode(artifactPath);
            console.log("Using pre-compiled bytecode from:", artifactPath);
        } else {
            bytecode = type(Veera).creationCode;
        }

        bytes memory creationCode = abi.encodePacked(
            bytecode,
            abi.encode(
                manifest.name, manifest.symbol, manifest.bootstrapAdmin, manifest.constructorSupply, manifest.maxSupply
            )
        );
        bytes32 initCodeHash = keccak256(creationCode);
        address predicted = vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);

        console.log("--------------------------------------------------");
        console.log("Init code hash:    ");
        console.logBytes32(initCodeHash);
        console.log("Predicted address: ", predicted);
        console.log("Expected address:  ", manifest.expectedTokenAddress);
        console.log("--------------------------------------------------");

        if (block.chainid == 31337 && manifest.expectedTokenAddress == address(0)) {
            console.log("WARNING: expectedTokenAddress is zero. Bootstrapping mode active on local anvil.");
        } else {
            require(manifest.expectedTokenAddress != address(0), "expectedTokenAddress must be set on public chains");
            require(predicted == manifest.expectedTokenAddress, "Predicted address mismatch");
        }

        // Dry-run mode check
        bool dryRun = vm.envOr("DRY_RUN", false);
        if (dryRun) {
            console.log("------------------ DRY RUN ACTIVE ----------------");
            console.log("Would deploy Veera to predicted address: ", predicted);
            console.log("Salt:                                    ", vm.toString(manifest.salt));
            console.log("Bootstrap Admin:                         ", manifest.bootstrapAdmin);
            console.log("Target Admin:                            ", manifest.targetAdmin);
            console.log("Initial Supply:                          ", manifest.expectedPostDeploymentSupply);
            console.log("--------------------------------------------------");
            return (Veera(predicted), config);
        }

        // Pre-deploy check: verify if the token has been deployed already
        uint256 predictedCodeSize;
        assembly {
            predictedCodeSize := extcodesize(predicted)
        }

        Veera token;
        if (predictedCodeSize > 0) {
            console.log("WARNING: Contract already deployed at predicted address:", predicted);
            console.log("WARNING: Running in VERIFICATION-ONLY mode. No transactions will be broadcast.");
            token = Veera(predicted);
        } else {
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
            require(returnedData.length == 20, "Unexpected CREATE2 factory return data length");
            address deployedAddress;
            assembly {
                deployedAddress := shr(96, mload(add(returnedData, 0x20)))
            }
            require(deployedAddress == predicted, "Deployed address mismatch");
            token = Veera(deployedAddress);

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
        }

        // 7. Make role and supply handoff fail-closed
        console.log("Verifying final deployment state...");

        // Supply assertions
        require(token.totalSupply() == manifest.expectedPostDeploymentSupply, "Fail-closed: Total supply mismatch");

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
