// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HelperConfig, LOCAL_CHAINID} from "../script/HelperConfig.s.sol";

contract HelperConfigTest is Test {
    function test_BaseMainnetConfig() public {
        vm.chainId(8453);
        HelperConfig config = new HelperConfig();
        (address initialAdmin, uint256 initialSupply, uint256 maxSupply, string memory name, string memory symbol) =
            config.activeNetworkConfig();

        assertEq(initialAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(initialSupply, 1_000_000_000 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
    }

    function test_BaseSepoliaConfig() public {
        vm.chainId(84532);
        HelperConfig config = new HelperConfig();
        (address initialAdmin, uint256 initialSupply, uint256 maxSupply, string memory name, string memory symbol) =
            config.activeNetworkConfig();

        assertEq(initialAdmin, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(initialSupply, 1_000_000_000 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
    }

    function test_BSCMainnetConfig() public {
        vm.chainId(56);
        HelperConfig config = new HelperConfig();
        (address initialAdmin, uint256 initialSupply, uint256 maxSupply, string memory name, string memory symbol) =
            config.activeNetworkConfig();

        assertEq(initialAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(initialSupply, 0 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
    }

    function test_BSCTestnetConfig() public {
        vm.chainId(97);
        HelperConfig config = new HelperConfig();
        (address initialAdmin, uint256 initialSupply, uint256 maxSupply, string memory name, string memory symbol) =
            config.activeNetworkConfig();

        assertEq(initialAdmin, 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03);
        assertEq(initialSupply, 0 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
    }

    function test_LocalConfigFallback() public {
        vm.chainId(LOCAL_CHAINID);
        HelperConfig config = new HelperConfig();
        (address initialAdmin, uint256 initialSupply, uint256 maxSupply, string memory name, string memory symbol) =
            config.activeNetworkConfig();

        assertEq(initialAdmin, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(initialSupply, 1_000_000_000 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
    }

    function test_DeterministicConstructorArgs_MainnetsMatch() public {
        // Retrieve Base Mainnet deterministic args
        vm.chainId(8453);
        HelperConfig baseConfig = new HelperConfig();
        address mockDeployer = address(0x123);
        (
            string memory baseName,
            string memory baseSymbol,
            address baseConstructorAdmin,
            uint256 baseConstructorSupply,
            uint256 baseMaxSupply
        ) = baseConfig.getDeterministicConstructorArgs(mockDeployer);

        // Retrieve BSC Mainnet deterministic args
        vm.chainId(56);
        HelperConfig bscConfig = new HelperConfig();
        (
            string memory bscName,
            string memory bscSymbol,
            address bscConstructorAdmin,
            uint256 bscConstructorSupply,
            uint256 bscMaxSupply
        ) = bscConfig.getDeterministicConstructorArgs(mockDeployer);

        // Assert they are identical
        assertEq(baseName, bscName);
        assertEq(baseSymbol, bscSymbol);
        assertEq(baseConstructorAdmin, bscConstructorAdmin);
        assertEq(baseConstructorSupply, bscConstructorSupply);
        assertEq(baseMaxSupply, bscMaxSupply);

        // Assert supply is 0
        assertEq(baseConstructorSupply, 0);

        // Assert they match the expected mainnet values
        assertEq(baseConstructorAdmin, mockDeployer);
    }

    function test_DeterministicConstructorArgs_TestnetsMatch() public {
        // Retrieve Base Sepolia deterministic args
        vm.chainId(84532);
        HelperConfig baseConfig = new HelperConfig();
        address mockDeployer = address(0x123);
        (
            string memory baseName,
            string memory baseSymbol,
            address baseConstructorAdmin,
            uint256 baseConstructorSupply,
            uint256 baseMaxSupply
        ) = baseConfig.getDeterministicConstructorArgs(mockDeployer);

        // Retrieve BSC Testnet deterministic args
        vm.chainId(97);
        HelperConfig bscConfig = new HelperConfig();
        (
            string memory bscName,
            string memory bscSymbol,
            address bscConstructorAdmin,
            uint256 bscConstructorSupply,
            uint256 bscMaxSupply
        ) = bscConfig.getDeterministicConstructorArgs(mockDeployer);

        // Assert they are identical
        assertEq(baseName, bscName);
        assertEq(baseSymbol, bscSymbol);
        assertEq(baseConstructorAdmin, bscConstructorAdmin);
        assertEq(baseConstructorSupply, bscConstructorSupply);
        assertEq(baseMaxSupply, bscMaxSupply);

        // Assert supply is 0
        assertEq(baseConstructorSupply, 0);

        // Assert they match the expected testnet values (unified testnet admin)
        assertEq(baseConstructorAdmin, mockDeployer);
    }
}
