// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Veera} from "../src/Veera.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";
import {HelperConfig, LOCAL_CHAINID} from "./HelperConfig.s.sol";

contract DeployOFTAdapter is Script {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function run() external returns (VeeraMintBurnOFTAdapter, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (
            address initialAdmin,
            uint256 initialSupply,
            uint256 maxSupply,
            string memory name,
            string memory symbol,
            address lzEndpoint,
            // eid is not used in this script
        ) = config.activeNetworkConfig();

        // Retrieve the token address from environment or deploy a new one if local
        address tokenAddress = vm.envOr("VEERA_TOKEN_ADDRESS", address(0));

        if (tokenAddress == address(0)) {
            if (block.chainid == LOCAL_CHAINID) {
                console.log("No VEERA_TOKEN_ADDRESS provided. Deploying a new Veera token on local Anvil...");
                vm.startBroadcast();
                Veera deployedToken = new Veera(name, symbol, initialAdmin, initialSupply, maxSupply);
                tokenAddress = address(deployedToken);
                vm.stopBroadcast();
            } else {
                revert("Error: VEERA_TOKEN_ADDRESS environment variable must be specified for public networks");
            }
        }

        console.log("--------------------------------------------------");
        console.log("Deploying OFT Adapter to Chain ID:", block.chainid);
        console.log("Using Veera Token Address:        ", tokenAddress);
        console.log("LayerZero Endpoint V2 Address:    ", lzEndpoint);
        console.log("Delegate/Owner Address:           ", initialAdmin);
        console.log("--------------------------------------------------");

        require(lzEndpoint != address(0), "Error: LayerZero Endpoint address cannot be zero");
        require(initialAdmin != address(0), "Error: Delegate address cannot be zero");

        vm.startBroadcast();

        VeeraMintBurnOFTAdapter adapter = new VeeraMintBurnOFTAdapter(tokenAddress, lzEndpoint, initialAdmin);

        // Attempt to grant MINTER_ROLE to the adapter if deployer is the token admin
        Veera token = Veera(tokenAddress);
        if (token.hasRole(token.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            console.log("Deployer is Token Admin. Granting MINTER_ROLE to the adapter contract...");
            token.grantRole(MINTER_ROLE, address(adapter));
        } else {
            console.log("WARNING: Deployer is not Token Admin. MINTER_ROLE must be granted manually.");
            console.log("To grant the role, the Token Admin/Safe must call:");
            console.log("  Veera(%s).grantRole(MINTER_ROLE, %s);", tokenAddress, address(adapter));
        }

        vm.stopBroadcast();

        console.log("--------------------------------------------------");
        console.log("OFT ADAPTER DEPLOYMENT COMPLETE");
        console.log("Adapter Address:", address(adapter));
        console.log("--------------------------------------------------");

        return (adapter, config);
    }
}
