// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HelperConfig, LOCAL_CHAINID} from "../script/HelperConfig.s.sol";

contract HelperConfigTest is Test {
    function test_BaseMainnetConfig() public {
        vm.chainId(8453);
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "base_mainnet");
        assertEq(manifest.targetAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.initialMintRecipient, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
    }

    function test_BaseSepoliaConfig() public {
        vm.chainId(84532);
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "base_testnet");
        assertEq(manifest.targetAdmin, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(manifest.initialMintRecipient, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
    }

    function test_BSCMainnetConfig() public {
        vm.chainId(56);
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "bsc_mainnet");
        assertEq(manifest.targetAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.initialMintRecipient, address(0));
        assertEq(manifest.expectedPostDeploymentSupply, 0 ether);
    }

    function test_BSCTestnetConfig() public {
        vm.chainId(97);
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "bsc_testnet");
        assertEq(manifest.targetAdmin, 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03);
        assertEq(manifest.initialMintRecipient, address(0));
        assertEq(manifest.expectedPostDeploymentSupply, 0 ether);
    }

    function test_LocalConfigFallback() public {
        vm.chainId(LOCAL_CHAINID);
        HelperConfig config = new HelperConfig();
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        assertEq(manifest.rpcIdentifier, "local_anvil");
        assertEq(manifest.targetAdmin, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(manifest.initialMintRecipient, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
    }

    function test_constructorArgsAreIdenticalAcrossMainnets() public {
        // Retrieve Base Mainnet deterministic args
        vm.chainId(8453);
        HelperConfig baseConfig = new HelperConfig();
        (
            string memory baseName,
            string memory baseSymbol,
            address baseConstructorAdmin,
            uint256 baseConstructorSupply,
            uint256 baseMaxSupply
        ) = baseConfig.getDeterministicConstructorArgs();

        // Retrieve BSC Mainnet deterministic args
        vm.chainId(56);
        HelperConfig bscConfig = new HelperConfig();
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

        // Assert bootstrap admin is correct EOA
        assertEq(baseConstructorAdmin, 0x3188aF25805b403006c49e9D387FB17bb65A9f25);
    }

    function test_constructorArgsAreIdenticalAcrossTestnets() public {
        // Retrieve Base Sepolia deterministic args
        vm.chainId(84532);
        HelperConfig baseConfig = new HelperConfig();
        (
            string memory baseName,
            string memory baseSymbol,
            address baseConstructorAdmin,
            uint256 baseConstructorSupply,
            uint256 baseMaxSupply
        ) = baseConfig.getDeterministicConstructorArgs();

        // Retrieve BSC Testnet deterministic args
        vm.chainId(97);
        HelperConfig bscConfig = new HelperConfig();
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

        // Assert bootstrap admin is correct EOA
        assertEq(baseConstructorAdmin, 0x3188aF25805b403006c49e9D387FB17bb65A9f25);
    }
}
