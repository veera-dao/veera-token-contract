// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";

contract ConfigureOFTAdapter is Script {
    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function run() external {
        address adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
        uint32 peerEid = uint32(vm.envUint("PEER_EID"));
        address peerAddress = vm.envAddress("PEER_ADDRESS");

        require(adapterAddress != address(0), "Error: ADAPTER_ADDRESS cannot be zero");
        require(peerEid != 0, "Error: PEER_EID cannot be zero");
        require(peerAddress != address(0), "Error: PEER_ADDRESS cannot be zero");

        console.log("--------------------------------------------------");
        console.log("Configuring peer on OFT Adapter:");
        console.log("Local Adapter:       ", adapterAddress);
        console.log("Remote Endpoint ID:  ", peerEid);
        console.log("Remote Peer Address: ", peerAddress);
        console.log("--------------------------------------------------");

        bytes32 peerBytes32 = addressToBytes32(peerAddress);

        vm.startBroadcast();

        VeeraMintBurnOFTAdapter adapter = VeeraMintBurnOFTAdapter(adapterAddress);
        adapter.setPeer(peerEid, peerBytes32);

        vm.stopBroadcast();

        console.log("--------------------------------------------------");
        console.log("PEER CONFIGURATION COMPLETE");
        console.log("--------------------------------------------------");
    }
}
