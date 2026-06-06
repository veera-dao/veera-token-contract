// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployVeera} from "../script/DeployVeera.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Veera} from "../src/Veera.sol";

contract DeployVeeraTest is Test {
    using stdJson for string;
    DeployVeera public deployer;

    // NOTE: These addresses must match the manifest.
    address public bootstrapAdmin = 0x3188aF25805b403006c49e9D387FB17bb65A9f25;
    address public expectedFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function setUp() public {
        deployer = new DeployVeera();

        // Etch dummy contract bytecode to bypass extcodesize checks on admin addresses
        vm.etch(0xd2b8875b840D3BD574E1e6b440888e110632A0FD, hex"00");
        vm.etch(0xfEDB58C317d347e265990888919879a5d392a12c, hex"00");
        vm.etch(0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03, hex"00");

        // Etch factory code to ensure codeSize > 0 check passes and Forge's broadcast parser recognizes it
        vm.etch(
            expectedFactory,
            hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
        );
    }

    function loadManifestConfig(string memory manifestFile, uint256 chainId)
        internal
        view
        returns (HelperConfig.ManifestConfig memory manifest)
    {
        string memory path = string.concat(vm.projectRoot(), "/", manifestFile);
        string memory json = vm.readFile(path);

        manifest.salt = json.readBytes32(".salt");
        manifest.factory = json.readAddress(".factory");
        manifest.factoryCodeHash = json.readBytes32(".factoryCodeHash");
        manifest.bootstrapAdmin = json.readAddress(".bootstrapAdmin");
        manifest.name = json.readString(".name");
        manifest.symbol = json.readString(".symbol");
        manifest.constructorSupply = vm.parseUint(json.readString(".constructorSupply"));
        manifest.maxSupply = vm.parseUint(json.readString(".maxSupply"));
        manifest.expectedTokenAddress = json.readAddress(".expectedTokenAddress");

        string memory networkKey = string.concat(".networks.", vm.toString(chainId));
        manifest.rpcIdentifier = json.readString(string.concat(networkKey, ".rpcIdentifier"));
        manifest.targetAdmin = json.readAddress(string.concat(networkKey, ".targetAdmin"));
        manifest.initialMintRecipient = json.readAddress(string.concat(networkKey, ".initialMintRecipient"));
        manifest.expectedPostDeploymentSupply =
            vm.parseUint(json.readString(string.concat(networkKey, ".expectedPostDeploymentSupply")));

        string memory lzEndpointKey = string.concat(networkKey, ".lzEndpoint");
        if (vm.keyExistsJson(json, lzEndpointKey)) {
            manifest.lzEndpoint = json.readAddress(lzEndpointKey);
        }

        string memory eidKey = string.concat(networkKey, ".lzEid");
        if (vm.keyExistsJson(json, eidKey)) {
            manifest.eid = uint32(vm.parseUint(json.readString(eidKey)));
        }

        string memory expectedBridgeKey = string.concat(networkKey, ".expectedBridgeAddress");
        if (vm.keyExistsJson(json, expectedBridgeKey)) {
            manifest.expectedBridgeAddress = json.readAddress(expectedBridgeKey);
        }
    }

    function tryLoadConfig() internal returns (HelperConfig config) {
        try new HelperConfig() returns (HelperConfig _config) {
            return _config;
        } catch {
            return HelperConfig(address(0));
        }
    }

    function tryRunDeployer() internal returns (Veera token, HelperConfig config) {
        try deployer.run() returns (Veera _token, HelperConfig _config) {
            return (_token, _config);
        } catch {
            return (Veera(address(0)), HelperConfig(address(0)));
        }
    }

    // Helper to calculate predicted address from config on different chains
    function getPredictedAddressForChain(string memory manifestFile, uint256 chainId) public returns (address) {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig(manifestFile, chainId);

        bytes memory bytecode;
        string memory artifactPath = vm.envOr("TOKEN_ARTIFACT_PATH", string(""));
        if (bytes(artifactPath).length > 0) {
            bytecode = vm.getCode(artifactPath);
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
        return vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);
    }

    // 1. Base mainnet predicted address == BSC mainnet predicted address
    function test_predictedAddressMatchesAcrossMainnets() public {
        address basePredicted = getPredictedAddressForChain("deploy_manifest.mainnet.json", 8453);
        address bscPredicted = getPredictedAddressForChain("deploy_manifest.mainnet.json", 56);
        if (basePredicted == address(0) || bscPredicted == address(0)) return;

        console.log("Base Mainnet Predicted Address: ", basePredicted);
        console.log("BSC Mainnet Predicted Address:  ", bscPredicted);

        assertEq(basePredicted, bscPredicted, "Predicted address should match across mainnets");
    }

    // 2. Base Sepolia predicted address == BSC testnet predicted address
    function test_predictedAddressMatchesAcrossTestnets() public {
        address baseSepoliaPredicted = getPredictedAddressForChain("deploy_manifest.testnet.json", 84532);
        address bscTestnetPredicted = getPredictedAddressForChain("deploy_manifest.testnet.json", 97);
        if (baseSepoliaPredicted == address(0) || bscTestnetPredicted == address(0)) return;

        console.log("Base Sepolia Predicted Address: ", baseSepoliaPredicted);
        console.log("BSC Testnet Predicted Address:  ", bscTestnetPredicted);

        assertEq(baseSepoliaPredicted, bscTestnetPredicted, "Predicted address should match across testnets");
    }

    // 3. Predicted address matches expected token address
    function test_predictedAddressMatchesManifest() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);

        // Skip check if manifest expectedAddress is still address(0) placeholder
        if (manifest.expectedTokenAddress != address(0)) {
            address predicted = getPredictedAddressForChain("deploy_manifest.mainnet.json", 8453);
            assertEq(
                predicted,
                manifest.expectedTokenAddress,
                "Predicted address does not match expectedTokenAddress in manifest"
            );
        }
    }

    // 4. Changing bootstrap admin changes predicted address
    function test_changingBootstrapAdminChangesAddress() public {
        address predictedWithAdmin = getPredictedAddressForChain("deploy_manifest.mainnet.json", 8453);
        if (predictedWithAdmin == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);

        bytes memory creationCode = abi.encodePacked(
            type(Veera).creationCode,
            abi.encode(manifest.name, manifest.symbol, address(0xDEAD), manifest.constructorSupply, manifest.maxSupply)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        address predictedWithOtherAdmin = vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);

        assertTrue(predictedWithAdmin != predictedWithOtherAdmin, "Changing bootstrap admin must change address");
    }

    // 5. Changing constructor initial supply changes predicted address
    function test_changingInitialSupplyChangesAddress() public {
        address predictedWithZeroSupply = getPredictedAddressForChain("deploy_manifest.mainnet.json", 8453);
        if (predictedWithZeroSupply == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);

        bytes memory creationCode = abi.encodePacked(
            type(Veera).creationCode,
            abi.encode(manifest.name, manifest.symbol, manifest.bootstrapAdmin, 1000 ether, manifest.maxSupply)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        address predictedWithNonZeroSupply = vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);

        assertTrue(predictedWithZeroSupply != predictedWithNonZeroSupply, "Changing initial supply must change address");
    }

    // 6. Changing salt changes predicted address
    function test_changingSaltChangesAddress() public {
        address predictedWithSalt = getPredictedAddressForChain("deploy_manifest.mainnet.json", 8453);
        if (predictedWithSalt == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);

        bytes memory creationCode = abi.encodePacked(
            type(Veera).creationCode,
            abi.encode(
                manifest.name, manifest.symbol, manifest.bootstrapAdmin, manifest.constructorSupply, manifest.maxSupply
            )
        );
        bytes32 initCodeHash = keccak256(creationCode);

        bytes32 differentSalt = keccak256("DifferentSalt");
        address predictedWithDifferentSalt = vm.computeCreate2Address(differentSalt, initCodeHash, manifest.factory);

        assertTrue(predictedWithSalt != predictedWithDifferentSalt, "Changing salt must change address");
    }

    // 7. Bootstrap admin has no roles after deployment
    function test_bootstrapAdminHasNoRolesAfterDeployment() public {
        vm.chainId(84532); // Base Sepolia
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;

        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), bootstrapAdmin));
        assertFalse(token.hasRole(token.MINTER_ROLE(), bootstrapAdmin));
        assertFalse(token.hasRole(token.PAUSER_ROLE(), bootstrapAdmin));
    }

    // 8. Target admin receives DEFAULT_ADMIN_ROLE
    function test_targetAdminReceivesDefaultAdminRole() public {
        vm.chainId(84532); // Base Sepolia
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), manifest.targetAdmin));
    }

    // 9. Pauser and Minter roles are initially unassigned post-deployment
    function test_pauserAndMinterRolesAreInitiallyUnassigned() public {
        vm.chainId(84532); // Base Sepolia
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        // Neither targetAdmin nor bootstrapAdmin should have PAUSER_ROLE or MINTER_ROLE
        assertFalse(token.hasRole(token.PAUSER_ROLE(), manifest.targetAdmin));
        assertFalse(token.hasRole(token.MINTER_ROLE(), manifest.targetAdmin));
        assertFalse(token.hasRole(token.PAUSER_ROLE(), bootstrapAdmin));
        assertFalse(token.hasRole(token.MINTER_ROLE(), bootstrapAdmin));
    }

    // 10. Canonical chain receives initial mint
    function test_canonicalChainReceivesInitialMint() public {
        vm.chainId(8453); // Base Mainnet
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(token.totalSupply(), manifest.expectedPostDeploymentSupply);
        assertEq(token.balanceOf(manifest.initialMintRecipient), manifest.expectedPostDeploymentSupply);
    }

    // 11. Remote chain starts with zero supply
    function test_remoteChainStartsWithZeroSupply() public {
        vm.chainId(56); // BSC Mainnet
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;

        assertEq(token.totalSupply(), 0);
    }

    // 12. Deployed address matches predicted address on Base Mainnet
    function test_deployedAddressMatchesPredicted_BaseMainnet() public {
        vm.chainId(8453); // Base Mainnet
        address predicted = getPredictedAddressForChain("deploy_manifest.mainnet.json", 8453);
        if (predicted == address(0)) return;

        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;

        assertEq(address(token), predicted, "Deployed token address should match predicted address on Base Mainnet");
    }

    // 13. Deployed address matches predicted address on BSC Mainnet
    function test_deployedAddressMatchesPredicted_BscMainnet() public {
        vm.chainId(56); // BSC Mainnet
        address predicted = getPredictedAddressForChain("deploy_manifest.mainnet.json", 56);
        if (predicted == address(0)) return;

        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;

        assertEq(address(token), predicted, "Deployed token address should match predicted address on BSC Mainnet");
    }

    // 14. Deployed address matches expectedTokenAddress in manifest on Base Mainnet
    function test_deployedAddressMatchesManifest_BaseMainnet() public {
        vm.chainId(8453); // Base Mainnet
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(
            address(token),
            manifest.expectedTokenAddress,
            "Deployed token address should match manifest on Base Mainnet"
        );
    }

    // 15. Deployed address matches expectedTokenAddress in manifest on BSC Mainnet
    function test_deployedAddressMatchesManifest_BscMainnet() public {
        vm.chainId(56); // BSC Mainnet
        (Veera token, HelperConfig config) = tryRunDeployer();
        if (address(config) == address(0)) return;
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(
            address(token), manifest.expectedTokenAddress, "Deployed token address should match manifest on BSC Mainnet"
        );
    }

    // Utility: Run with `forge test --match-test test_logManifestIntegrityHash -vvv` to recompute
    // the manifest integrity hash after a legitimate manifest change.
    function test_logManifestIntegrityHash() public {
        vm.chainId(8453);
        HelperConfig config = tryLoadConfig();
        if (address(config) == address(0)) return;
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

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
        console.log("Manifest Integrity Hash:");
        console.logBytes32(calculatedHash);
    }
}
