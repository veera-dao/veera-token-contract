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
            // CRITICAL: Mainnet Gnosis Safe.
            adminAddress = 0x0000000000000000000000000000000000000000;
        } 
        else if (block.chainid == 84532) {
            // CRITICAL: Base Sepolia (Testnet Safe / Dev Wallet).
            adminAddress = 0x0000000000000000000000000000000000000000;
        } 
        else {
            // Local / Anvil (Default Foundry Sender) (common known address)
            adminAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        }

        // Validate zero addresses are not used
        require(adminAddress != address(0), "HelperConfig: Admin address cannot be zero");

        activeNetworkConfig = NetworkConfig({
            initialAdmin: adminAddress,
            initialSupply: INITIAL_SUPPLY,
            maxSupply: MAX_SUPPLY,
            name: NAME,
            symbol: SYMBOL
        });
    }
}