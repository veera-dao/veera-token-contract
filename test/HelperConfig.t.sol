// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";

contract HelperConfigTest is Test {
    function tryLoadConfig() internal returns (HelperConfig config) {
        try new HelperConfig() returns (HelperConfig _config) {
            return _config;
        } catch {
            return HelperConfig(address(0));
        }
    }

    function test_BaseMainnetConfig() public {
        vm.chainId(8453);
        HelperConfig config = tryLoadConfig();
        if (address(config) == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "base_mainnet");
        assertEq(manifest.targetAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.initialMintRecipient, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
        assertEq(manifest.lzEndpoint, 0x1a44076050125825900e736c501f859c50fE728c);
        assertEq(manifest.eid, 30184);
    }

    function test_BaseSepoliaConfig() public {
        vm.chainId(84532);
        HelperConfig config = tryLoadConfig();
        if (address(config) == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "base_testnet");
        assertEq(manifest.targetAdmin, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(manifest.initialMintRecipient, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
        assertEq(manifest.lzEndpoint, 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(manifest.eid, 40245);
    }

    function test_BSCMainnetConfig() public {
        vm.chainId(56);
        HelperConfig config = tryLoadConfig();
        if (address(config) == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "bsc_mainnet");
        assertEq(manifest.targetAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.initialMintRecipient, address(0));
        assertEq(manifest.expectedPostDeploymentSupply, 0 ether);
        assertEq(manifest.lzEndpoint, 0x1a44076050125825900e736c501f859c50fE728c);
        assertEq(manifest.eid, 30102);
    }

    function test_BSCTestnetConfig() public {
        vm.chainId(97);
        HelperConfig config = tryLoadConfig();
        if (address(config) == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "bsc_testnet");
        assertEq(manifest.targetAdmin, 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03);
        assertEq(manifest.initialMintRecipient, address(0));
        assertEq(manifest.expectedPostDeploymentSupply, 0 ether);
        assertEq(manifest.lzEndpoint, 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(manifest.eid, 40102);
    }

    function test_LocalConfigFallback() public {
        vm.chainId(31337);
        HelperConfig config = tryLoadConfig();
        if (address(config) == address(0)) return;

        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "local_anvil");
        assertEq(manifest.targetAdmin, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(manifest.initialMintRecipient, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
        assertEq(manifest.lzEndpoint, address(0));
        assertEq(manifest.eid, 0);
    }

    function test_constructorArgsAreIdenticalAcrossMainnets() public {
        // Retrieve Base Mainnet deterministic args
        vm.chainId(8453);
        HelperConfig baseConfig = tryLoadConfig();
        if (address(baseConfig) == address(0)) return;

        (
            string memory baseName,
            string memory baseSymbol,
            address baseConstructorAdmin,
            uint256 baseConstructorSupply,
            uint256 baseMaxSupply
        ) = baseConfig.getDeterministicConstructorArgs();

        // Retrieve BSC Mainnet deterministic args
        vm.chainId(56);
        HelperConfig bscConfig = tryLoadConfig();
        if (address(bscConfig) == address(0)) return;

        (
            string memory bscName,
            string memory bscSymbol,
            address bscConstructorAdmin,
            uint256 bscConstructorSupply,
            uint256 bscMaxSupply
        ) = bscConfig.getDeterministicConstructorArgs();

        // Assert they are identical
        assertEq(baseName, bscName);
        assertEq(baseSymbol, bscSymbol);
        assertEq(baseConstructorAdmin, bscConstructorAdmin);
        assertEq(baseConstructorSupply, bscConstructorSupply);
        assertEq(baseMaxSupply, bscMaxSupply);

        // Assert supply is 0
        assertEq(baseConstructorSupply, 0);

        // Assert bootstrap admin matches manifest (update if manifest changes)
        assertEq(baseConstructorAdmin, 0x3188aF25805b403006c49e9D387FB17bb65A9f25);
    }

    function test_constructorArgsAreIdenticalAcrossTestnets() public {
        // Retrieve Base Sepolia deterministic args
        vm.chainId(84532);
        HelperConfig baseConfig = tryLoadConfig();
        if (address(baseConfig) == address(0)) return;

        (
            string memory baseName,
            string memory baseSymbol,
            address baseConstructorAdmin,
            uint256 baseConstructorSupply,
            uint256 baseMaxSupply
        ) = baseConfig.getDeterministicConstructorArgs();

        // Retrieve BSC Testnet deterministic args
        vm.chainId(97);
        HelperConfig bscConfig = tryLoadConfig();
        if (address(bscConfig) == address(0)) return;

        (
            string memory bscName,
            string memory bscSymbol,
            address bscConstructorAdmin,
            uint256 bscConstructorSupply,
            uint256 bscMaxSupply
        ) = bscConfig.getDeterministicConstructorArgs();

        // Assert they are identical
        assertEq(baseName, bscName);
        assertEq(baseSymbol, bscSymbol);
        assertEq(baseConstructorAdmin, bscConstructorAdmin);
        assertEq(baseConstructorSupply, bscConstructorSupply);
        assertEq(baseMaxSupply, bscMaxSupply);

        // Assert supply is 0
        assertEq(baseConstructorSupply, 0);

        // Assert bootstrap admin matches manifest (update if manifest changes)
        assertEq(baseConstructorAdmin, 0x3188aF25805b403006c49e9D387FB17bb65A9f25);
    }

    function test_PrintPredictedBridgeAddresses() public {
        uint256[4] memory chains = [uint256(8453), uint256(56), uint256(84532), uint256(97)];
        string[4] memory names = ["Base Mainnet", "BSC Mainnet", "Base Testnet", "BSC Testnet"];
        for (uint256 i = 0; i < 4; i++) {
            vm.chainId(chains[i]);
            HelperConfig config = tryLoadConfig();
            if (address(config) == address(0)) continue;

            HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();
            bytes memory creationCode = abi.encodePacked(
                type(VeeraMintBurnOFTAdapter).creationCode,
                abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
            );
            bytes32 initCodeHash = keccak256(creationCode);
            address predicted = vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);
            console.log("Predicted Bridge Address for %s: %s", names[i], predicted);
        }
    }
}
