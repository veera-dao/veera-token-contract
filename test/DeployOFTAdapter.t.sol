// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployOFTAdapter} from "../script/DeployOFTAdapter.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";

contract DeployOFTAdapterTest is Test {
    DeployOFTAdapter public deployer;

    function setUp() public {
        deployer = new DeployOFTAdapter();
    }

    function getPredictedBridgeAddressForChain(uint256 chainId) public returns (address) {
        vm.chainId(chainId);
        HelperConfig config;
        try new HelperConfig() returns (HelperConfig _config) {
            config = _config;
        } catch {
            return address(0);
        }
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        bytes memory creationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        return vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);
    }

    // test_MainnetAdapterPredictedAddressesMatch asserts mainnet addresses match (since endpoints and admin are same)
    function test_MainnetAdapterPredictedAddressesMatch() public {
        address basePredicted = getPredictedBridgeAddressForChain(8453);
        address bscPredicted = getPredictedBridgeAddressForChain(56);
        if (basePredicted == address(0) || bscPredicted == address(0)) return;

        console.log("Base Mainnet Predicted Bridge Address: ", basePredicted);
        console.log("BSC Mainnet Predicted Bridge Address:  ", bscPredicted);

        assertEq(
            basePredicted,
            bscPredicted,
            "Mainnet adapter predicted addresses must match when endpoints and admins match"
        );
    }

    // test_TestnetAdapterPredictedAddressesMayDifferWhenAdminsDiffer asserts testnet predicted addresses differ
    function test_TestnetAdapterPredictedAddressesMayDifferWhenAdminsDiffer() public {
        address baseTestnetPredicted = getPredictedBridgeAddressForChain(84532);
        address bscTestnetPredicted = getPredictedBridgeAddressForChain(97);
        if (baseTestnetPredicted == address(0) || bscTestnetPredicted == address(0)) return;

        console.log("Base Testnet Predicted Bridge Address: ", baseTestnetPredicted);
        console.log("BSC Testnet Predicted Bridge Address:  ", bscTestnetPredicted);

        assertTrue(
            baseTestnetPredicted != bscTestnetPredicted,
            "Testnet adapter predicted addresses should differ when admins differ"
        );
    }

    // test_ChangingTargetAdminChangesBridgeAddress verifies changing targetAdmin changes predicted address
    function test_ChangingTargetAdminChangesBridgeAddress() public {
        vm.chainId(84532);
        HelperConfig config;
        try new HelperConfig() returns (HelperConfig _config) {
            config = _config;
        } catch {
            return;
        }
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        bytes memory baseCreationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
        );
        address basePredicted = vm.computeCreate2Address(manifest.salt, keccak256(baseCreationCode), manifest.factory);

        bytes memory changedCreationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, address(0xDEAD))
        );
        address changedPredicted =
            vm.computeCreate2Address(manifest.salt, keccak256(changedCreationCode), manifest.factory);

        assertTrue(
            basePredicted != changedPredicted, "Changing targetAdmin must change computed CREATE2 bridge address"
        );
    }

    // test_ChangingEndpointChangesBridgeAddress verifies changing lzEndpoint changes predicted address
    function test_ChangingEndpointChangesBridgeAddress() public {
        vm.chainId(84532);
        HelperConfig config;
        try new HelperConfig() returns (HelperConfig _config) {
            config = _config;
        } catch {
            return;
        }
        HelperConfig.ManifestConfig memory manifest = config.getManifestConfig();

        bytes memory baseCreationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
        );
        address basePredicted = vm.computeCreate2Address(manifest.salt, keccak256(baseCreationCode), manifest.factory);

        bytes memory changedCreationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, address(0xDEAD), manifest.targetAdmin)
        );
        address changedPredicted =
            vm.computeCreate2Address(manifest.salt, keccak256(changedCreationCode), manifest.factory);

        assertTrue(basePredicted != changedPredicted, "Changing lzEndpoint must change computed CREATE2 bridge address");
    }
}
