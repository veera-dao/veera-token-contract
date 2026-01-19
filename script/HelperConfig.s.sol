// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

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

        if (block.chainid == 8453) {
            // Base Mainnet
            adminAddress = 0xd2b8875b840D3BD574E1e6b440888e110632A0FD;
        } else if (block.chainid == 84532) {
            // Base Sepolia Testnet
            adminAddress = 0xfEDB58C317d347e265990888919879a5d392a12c;
        } else {
            // Local / Anvil (Default Foundry Sender) (common known address)
            adminAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }

        // Validate zero addresses are not used
        require(adminAddress != address(0), "HelperConfig: Admin address cannot be zero");

        activeNetworkConfig = NetworkConfig({
            initialAdmin: adminAddress, initialSupply: INITIAL_SUPPLY, maxSupply: MAX_SUPPLY, name: NAME, symbol: SYMBOL
        });
    }
}
