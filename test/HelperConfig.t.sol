// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HelperConfig, LOCAL_CHAINID} from "../script/HelperConfig.s.sol";

contract HelperConfigTest is Test {
    function test_BaseMainnetConfig() public {
        vm.chainId(8453);
        HelperConfig config = new HelperConfig();
        (
            address initialAdmin,
            uint256 initialSupply,
            uint256 maxSupply,
            string memory name,
            string memory symbol,
            address lzEndpoint,
            uint32 eid
        ) = config.activeNetworkConfig();

        assertEq(initialAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(initialSupply, 1_000_000_000 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
        assertEq(lzEndpoint, 0x1a44076050125825900e736c501f859c50fE728c);
        assertEq(eid, 30184);
    }

    function test_BaseSepoliaConfig() public {
        vm.chainId(84532);
        HelperConfig config = new HelperConfig();
        (
            address initialAdmin,
            uint256 initialSupply,
            uint256 maxSupply,
            string memory name,
            string memory symbol,
            address lzEndpoint,
            uint32 eid
        ) = config.activeNetworkConfig();

        assertEq(initialAdmin, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(initialSupply, 1_000_000_000 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
        assertEq(lzEndpoint, 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(eid, 40245);
    }

    function test_BSCMainnetConfig() public {
        vm.chainId(56);
        HelperConfig config = new HelperConfig();
        (
            address initialAdmin,
            uint256 initialSupply,
            uint256 maxSupply,
            string memory name,
            string memory symbol,
            address lzEndpoint,
            uint32 eid
        ) = config.activeNetworkConfig();

        assertEq(initialAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(initialSupply, 0 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
        assertEq(lzEndpoint, 0x1a44076050125825900e736c501f859c50fE728c);
        assertEq(eid, 30102);
    }

    function test_BSCTestnetConfig() public {
        vm.chainId(97);
        HelperConfig config = new HelperConfig();
        (
            address initialAdmin,
            uint256 initialSupply,
            uint256 maxSupply,
            string memory name,
            string memory symbol,
            address lzEndpoint,
            uint32 eid
        ) = config.activeNetworkConfig();

        assertEq(initialAdmin, 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03);
        assertEq(initialSupply, 0 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
        assertEq(lzEndpoint, 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(eid, 40102);
    }

    function test_LocalConfigFallback() public {
        vm.chainId(LOCAL_CHAINID);
        HelperConfig config = new HelperConfig();
        (
            address initialAdmin,
            uint256 initialSupply,
            uint256 maxSupply,
            string memory name,
            string memory symbol,
            address lzEndpoint,
            uint32 eid
        ) = config.activeNetworkConfig();

        assertEq(initialAdmin, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(initialSupply, 1_000_000_000 ether);
        assertEq(maxSupply, 1_000_000_000 ether);
        assertEq(name, "Veera Token");
        assertEq(symbol, "VEERA");
        assertEq(lzEndpoint, address(0));
        assertEq(eid, 0);
    }
}
