// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {BaseERC20} from "../src/BaseERC20.sol";

contract DeployBaseERC20 is Script {
    function run() external returns (BaseERC20 token) {
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");
        address tokenOwner = vm.envAddress("TOKEN_OWNER");
        uint256 initialSupply = vm.envUint("TOKEN_INITIAL_SUPPLY");

        vm.startBroadcast();
        token = new BaseERC20(name, symbol, tokenOwner, initialSupply);
        vm.stopBroadcast();
    }
}
