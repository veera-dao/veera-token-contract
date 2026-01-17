// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Veera} from "../src/Veera.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployVeera is Script {
    function run() external returns (Veera, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address initialAdmin, uint256 initialSupply, uint256 maxSupply, string memory name, string memory symbol) =
            config.activeNetworkConfig();

        require(initialAdmin != address(0), "Error: Admin Address cannot be zero");
        require(bytes(name).length > 0, "Error: Token name cannot be empty");
        require(bytes(symbol).length > 0, "Error: Token symbol cannot be empty");
        require(maxSupply > 0, "Error: Max supply must be greater than zero");
        require(initialSupply <= maxSupply, "Error: Initial supply exceeds max supply");

        // Log chain ID for verification
        console.log("Deploying to Chain ID:", block.chainid);
        if (block.chainid != 8453 && block.chainid != 84532 && block.chainid != 31337) {
            console.log("WARNING: Unexpected chain ID. Verify RPC URL is correct!");
        }

        // Validate admin address for live networks
        if (block.chainid == 8453 || block.chainid == 84532) {
            // Check that admin is a contract (Gnosis Safe)
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(initialAdmin)
            }
            if (block.chainid == 8453) {
                require(codeSize > 0, "Error: Admin must be a contract (i.e. a Gnosis Safe)");
            } else if (codeSize == 0) {
                console.log("WARNING: Admin is not a contract (i.e. Gnosis Safe)");
            }
        }

        vm.startBroadcast();

        Veera token = new Veera(name, symbol, initialAdmin, initialSupply, maxSupply);

        vm.stopBroadcast();

        console.log("--------------------------------------------------");
        console.log("DEPLOYMENT COMPLETE");
        console.log("Chain ID:     ", block.chainid);
        console.log("Token Address:", address(token));
        console.log("Admin Address:", initialAdmin); // Verify this matches your expected Safe
        console.log("--------------------------------------------------");

        return (token, config);
    }
}
