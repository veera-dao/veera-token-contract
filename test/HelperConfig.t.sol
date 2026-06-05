// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";

contract HelperConfigTest is Test {
    using stdJson for string;

    function loadManifestConfig(string memory manifestFile, uint256 chainId)
        internal
        view
        returns (HelperConfig.ManifestConfig memory manifest)
    {
        string memory path = string.concat(vm.projectRoot(), "/", manifestFile);
        string memory json = vm.readFile(path);

        manifest.salt = json.readBytes32(".salt");
        manifest.factory = json.readAddress(".factory");
        manifest.factoryCodeHash = json.readBytes32(".factoryCodeHash");
        manifest.bootstrapAdmin = json.readAddress(".bootstrapAdmin");
        manifest.name = json.readString(".name");
        manifest.symbol = json.readString(".symbol");
        manifest.constructorSupply = vm.parseUint(json.readString(".constructorSupply"));
        manifest.maxSupply = vm.parseUint(json.readString(".maxSupply"));
        manifest.expectedTokenAddress = json.readAddress(".expectedTokenAddress");

        string memory networkKey = string.concat(".networks.", vm.toString(chainId));
        manifest.rpcIdentifier = json.readString(string.concat(networkKey, ".rpcIdentifier"));
        manifest.targetAdmin = json.readAddress(string.concat(networkKey, ".targetAdmin"));
        manifest.initialMintRecipient = json.readAddress(string.concat(networkKey, ".initialMintRecipient"));
        manifest.expectedPostDeploymentSupply =
            vm.parseUint(json.readString(string.concat(networkKey, ".expectedPostDeploymentSupply")));

        string memory lzEndpointKey = string.concat(networkKey, ".lzEndpoint");
        if (vm.keyExistsJson(json, lzEndpointKey)) {
            manifest.lzEndpoint = json.readAddress(lzEndpointKey);
        }

        string memory eidKey = string.concat(networkKey, ".lzEid");
        if (vm.keyExistsJson(json, eidKey)) {
            manifest.eid = uint32(vm.parseUint(json.readString(eidKey)));
        }

        string memory expectedBridgeKey = string.concat(networkKey, ".expectedBridgeAddress");
        if (vm.keyExistsJson(json, expectedBridgeKey)) {
            manifest.expectedBridgeAddress = json.readAddress(expectedBridgeKey);
        }
    }

    function test_BaseMainnetConfig() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);

        assertEq(manifest.rpcIdentifier, "base_mainnet");
        assertEq(manifest.targetAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.initialMintRecipient, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
        assertEq(manifest.lzEndpoint, 0x1a44076050125825900e736c501f859c50fE728c);
        assertEq(manifest.eid, 30184);
    }

    function test_BaseSepoliaConfig() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.testnet.json", 84532);

        assertEq(manifest.rpcIdentifier, "base_testnet");
        assertEq(manifest.targetAdmin, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(manifest.initialMintRecipient, 0xfEDB58C317d347e265990888919879a5d392a12c);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
        assertEq(manifest.lzEndpoint, 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(manifest.eid, 40245);
    }

    function test_BSCMainnetConfig() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.mainnet.json", 56);

        assertEq(manifest.rpcIdentifier, "bsc_mainnet");
        assertEq(manifest.targetAdmin, 0xd2b8875b840D3BD574E1e6b440888e110632A0FD);
        assertEq(manifest.initialMintRecipient, address(0));
        assertEq(manifest.expectedPostDeploymentSupply, 0 ether);
        assertEq(manifest.lzEndpoint, 0x1a44076050125825900e736c501f859c50fE728c);
        assertEq(manifest.eid, 30102);
    }

    function test_BSCTestnetConfig() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.testnet.json", 97);

        assertEq(manifest.rpcIdentifier, "bsc_testnet");
        assertEq(manifest.targetAdmin, 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03);
        assertEq(manifest.initialMintRecipient, address(0));
        assertEq(manifest.expectedPostDeploymentSupply, 0 ether);
        assertEq(manifest.lzEndpoint, 0x6EDCE65403992e310A62460808c4b910D972f10f);
        assertEq(manifest.eid, 40102);
    }

    function test_LocalConfigFallback() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.testnet.json", 31337);

        assertEq(manifest.rpcIdentifier, "local_anvil");
        assertEq(manifest.targetAdmin, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(manifest.initialMintRecipient, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(manifest.expectedPostDeploymentSupply, 1_000_000_000 ether);
        assertEq(manifest.lzEndpoint, address(0));
        assertEq(manifest.eid, 0);
    }

    function test_constructorArgsAreIdenticalAcrossMainnets() public {
        HelperConfig.ManifestConfig memory baseManifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);
        HelperConfig.ManifestConfig memory bscManifest = loadManifestConfig("deploy_manifest.mainnet.json", 56);

        // Assert they are identical for global parameters
        assertEq(baseManifest.name, bscManifest.name);
        assertEq(baseManifest.symbol, bscManifest.symbol);
        assertEq(baseManifest.bootstrapAdmin, bscManifest.bootstrapAdmin);
        assertEq(baseManifest.constructorSupply, bscManifest.constructorSupply);
        assertEq(baseManifest.maxSupply, bscManifest.maxSupply);

        // Assert supply is 0
        assertEq(baseManifest.constructorSupply, 0);

        // Assert bootstrap admin matches manifest (update if manifest changes)
        assertEq(baseManifest.bootstrapAdmin, 0x3188aF25805b403006c49e9D387FB17bb65A9f25);
    }

    function test_constructorArgsAreIdenticalAcrossTestnets() public {
        HelperConfig.ManifestConfig memory baseManifest = loadManifestConfig("deploy_manifest.testnet.json", 84532);
        HelperConfig.ManifestConfig memory bscManifest = loadManifestConfig("deploy_manifest.testnet.json", 97);

        // Assert they are identical for global parameters
        assertEq(baseManifest.name, bscManifest.name);
        assertEq(baseManifest.symbol, bscManifest.symbol);
        assertEq(baseManifest.bootstrapAdmin, bscManifest.bootstrapAdmin);
        assertEq(baseManifest.constructorSupply, bscManifest.constructorSupply);
        assertEq(baseManifest.maxSupply, bscManifest.maxSupply);

        // Assert supply is 0
        assertEq(baseManifest.constructorSupply, 0);

        // Assert bootstrap admin matches manifest (update if manifest changes)
        assertEq(baseManifest.bootstrapAdmin, 0x3188aF25805b403006c49e9D387FB17bb65A9f25);
    }

    function test_PrintPredictedBridgeAddresses() public {
        uint256[4] memory chains = [uint256(8453), uint256(56), uint256(84532), uint256(97)];
        string[4] memory names = ["Base Mainnet", "BSC Mainnet", "Base Testnet", "BSC Testnet"];
        string[4] memory manifests = [
            "deploy_manifest.mainnet.json",
            "deploy_manifest.mainnet.json",
            "deploy_manifest.testnet.json",
            "deploy_manifest.testnet.json"
        ];
        for (uint256 i = 0; i < 4; i++) {
            HelperConfig.ManifestConfig memory manifest = loadManifestConfig(manifests[i], chains[i]);

            bytes memory creationCode = abi.encodePacked(
                type(VeeraMintBurnOFTAdapter).creationCode,
                abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
            );
            bytes32 initCodeHash = keccak256(creationCode);
            address predicted = vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);
            console.log("Predicted Bridge Address for %s: %s", names[i], predicted);
        }
    }
}
