// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {BaseERC20} from "../src/BaseERC20.sol";

contract DeployBaseERC20 is Script {
    function run() external returns (BaseERC20 token) {
        string memory defaultName = "Veera";
        string memory defaultSymbol = "VEERA";
        uint256 defaultSupply = 1_000_000_000 ether;
        string memory name = vm.envOr("TOKEN_NAME", defaultName);
        string memory symbol = vm.envOr("TOKEN_SYMBOL", defaultSymbol);
        address tokenOwner = vm.envAddress("TOKEN_OWNER");
        uint256 initialSupply = vm.envOr("TOKEN_INITIAL_SUPPLY", defaultSupply);

        vm.startBroadcast();
        token = new BaseERC20(name, symbol, tokenOwner, initialSupply);
        vm.stopBroadcast();
    }
}
