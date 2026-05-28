// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

uint256 constant BASE_MAINNET_CHAINID = 8453;
uint256 constant BASE_SEPOLIA_CHAINID = 84532;
uint256 constant BSC_MAINNET_CHAINID = 56;
uint256 constant BSC_TESTNET_CHAINID = 97;
uint256 constant LOCAL_CHAINID = 31337;

address constant BASE_MAINNET_ADMIN = 0xd2b8875b840D3BD574E1e6b440888e110632A0FD;
address constant BASE_TESTNET_ADMIN = 0xfEDB58C317d347e265990888919879a5d392a12c;
address constant BSC_MAINNET_ADMIN = BASE_MAINNET_ADMIN;
address constant BSC_TESTNET_ADMIN = 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03;

contract HelperConfig is Script {
    struct NetworkConfig {
        address initialAdmin;
        uint256 initialSupply;
        uint256 maxSupply;
        string name;
        string symbol;
    }

    NetworkConfig public activeNetworkConfig;

    string constant NAME = "Veera Token";
    string constant SYMBOL = "VEERA";
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 ether;
    uint256 constant MAX_SUPPLY = INITIAL_SUPPLY;

    constructor() {
        address adminAddress;
        uint256 initialSupply = INITIAL_SUPPLY;

        if (block.chainid == BASE_MAINNET_CHAINID) {
            // Base Mainnet
            adminAddress = BASE_MAINNET_ADMIN;
        } else if (block.chainid == BASE_SEPOLIA_CHAINID) {
            // Base Sepolia Testnet
            adminAddress = BASE_TESTNET_ADMIN;
        } else if (block.chainid == BSC_MAINNET_CHAINID) {
            // BSC Mainnet (initial supply set to 0 as the token is bridged)
            adminAddress = BSC_MAINNET_ADMIN;
            initialSupply = 0 ether;
        } else if (block.chainid == BSC_TESTNET_CHAINID) {
            // BSC Testnet (initial supply set to 0 as the token is bridged)
            adminAddress = BSC_TESTNET_ADMIN;
            initialSupply = 0 ether;
        } else {
            // Local / Anvil (Default Foundry Sender) (common known address)
            adminAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }

        // Validate zero addresses are not used
        require(adminAddress != address(0), "HelperConfig: Admin address cannot be zero");

        activeNetworkConfig = NetworkConfig({
            initialAdmin: adminAddress, initialSupply: initialSupply, maxSupply: MAX_SUPPLY, name: NAME, symbol: SYMBOL
        });
    }
}
