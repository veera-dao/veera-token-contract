// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, stdJson} from "forge-std/Script.sol";

contract HelperConfig is Script {
    using stdJson for string;

    struct ManifestConfig {
        // Global deterministic parameters (affecting CREATE2 address)
        bytes32 salt;
        address factory;
        bytes32 factoryCodeHash;
        address bootstrapAdmin;
        string name;
        string symbol;
        uint256 constructorSupply;
        uint256 maxSupply;
        address expectedTokenAddress;

        // Per-chain target parameters (configured post-deployment)
        string rpcIdentifier;
        address targetAdmin;
        address initialMintRecipient;
        uint256 expectedPostDeploymentSupply;

        // LayerZero configuration
        address lzEndpoint;
        uint32 eid;
        address expectedBridgeAddress;
    }

    ManifestConfig public manifestConfig;

    constructor() {
        string memory manifestPath = vm.envString("DEPLOY_MANIFEST_PATH");
        string memory path = string.concat(vm.projectRoot(), "/", manifestPath);

        // Validate file existence
        require(vm.exists(path), string.concat("HelperConfig: deploy manifest file does not exist at ", path));

        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);

        // Validate existence of all global deterministic parameters
        require(vm.keyExistsJson(json, ".salt"), "HelperConfig: salt key missing in manifest");
        require(vm.keyExistsJson(json, ".factory"), "HelperConfig: factory key missing in manifest");
        require(vm.keyExistsJson(json, ".factoryCodeHash"), "HelperConfig: factoryCodeHash key missing in manifest");
        require(vm.keyExistsJson(json, ".bootstrapAdmin"), "HelperConfig: bootstrapAdmin key missing in manifest");
        require(vm.keyExistsJson(json, ".name"), "HelperConfig: name key missing in manifest");
        require(vm.keyExistsJson(json, ".symbol"), "HelperConfig: symbol key missing in manifest");
        require(vm.keyExistsJson(json, ".constructorSupply"), "HelperConfig: constructorSupply key missing in manifest");
        require(vm.keyExistsJson(json, ".maxSupply"), "HelperConfig: maxSupply key missing in manifest");
        require(
            vm.keyExistsJson(json, ".expectedTokenAddress"),
            "HelperConfig: expectedTokenAddress key missing in manifest"
        );

        manifestConfig.salt = json.readBytes32(".salt");
        manifestConfig.factory = json.readAddress(".factory");
        manifestConfig.factoryCodeHash = json.readBytes32(".factoryCodeHash");
        manifestConfig.bootstrapAdmin = json.readAddress(".bootstrapAdmin");
        manifestConfig.name = json.readString(".name");
        manifestConfig.symbol = json.readString(".symbol");
        manifestConfig.constructorSupply = vm.parseUint(json.readString(".constructorSupply"));
        manifestConfig.maxSupply = vm.parseUint(json.readString(".maxSupply"));
        manifestConfig.expectedTokenAddress = json.readAddress(".expectedTokenAddress");

        // Explicit validation checks for global values
        require(manifestConfig.salt != bytes32(0), "HelperConfig: salt cannot be zero");
        require(manifestConfig.factory != address(0), "HelperConfig: factory address cannot be zero");
        require(manifestConfig.factoryCodeHash != bytes32(0), "HelperConfig: factoryCodeHash cannot be zero");
        require(manifestConfig.bootstrapAdmin != address(0), "HelperConfig: bootstrapAdmin cannot be zero");
        require(bytes(manifestConfig.name).length > 0, "HelperConfig: token name cannot be empty");
        require(bytes(manifestConfig.symbol).length > 0, "HelperConfig: token symbol cannot be empty");
        require(manifestConfig.maxSupply > 0, "HelperConfig: maxSupply must be greater than zero");

        // Validate network configuration exists
        string memory networkKey = string.concat(".networks.", vm.toString(block.chainid));
        require(
            vm.keyExistsJson(json, networkKey),
            string.concat(
                "HelperConfig: Chain ID ",
                vm.toString(block.chainid),
                " is not configured in networks section of manifest"
            )
        );

        manifestConfig.rpcIdentifier = json.readString(string.concat(networkKey, ".rpcIdentifier"));
        manifestConfig.targetAdmin = json.readAddress(string.concat(networkKey, ".targetAdmin"));
        manifestConfig.initialMintRecipient = json.readAddress(string.concat(networkKey, ".initialMintRecipient"));
        manifestConfig.expectedPostDeploymentSupply =
            vm.parseUint(json.readString(string.concat(networkKey, ".expectedPostDeploymentSupply")));

        // Explicit validation checks for network values
        require(bytes(manifestConfig.rpcIdentifier).length > 0, "HelperConfig: rpcIdentifier cannot be empty");
        require(manifestConfig.targetAdmin != address(0), "HelperConfig: targetAdmin cannot be zero");
        if (manifestConfig.expectedPostDeploymentSupply > 0) {
            require(
                manifestConfig.initialMintRecipient != address(0),
                "HelperConfig: initialMintRecipient cannot be zero when expectedPostDeploymentSupply > 0"
            );
        }

        // Load LayerZero config if present in the manifest (otherwise fallback to default values)
        string memory lzEndpointKey = string.concat(networkKey, ".lzEndpoint");
        if (vm.keyExistsJson(json, lzEndpointKey)) {
            manifestConfig.lzEndpoint = json.readAddress(lzEndpointKey);
        } else {
            manifestConfig.lzEndpoint = address(0);
        }

        string memory eidKey = string.concat(networkKey, ".lzEid");
        if (vm.keyExistsJson(json, eidKey)) {
            manifestConfig.eid = uint32(vm.parseUint(json.readString(eidKey)));
        } else {
            manifestConfig.eid = 0;
        }

        string memory expectedBridgeKey = string.concat(networkKey, ".expectedBridgeAddress");
        if (vm.keyExistsJson(json, expectedBridgeKey)) {
            manifestConfig.expectedBridgeAddress = json.readAddress(expectedBridgeKey);
        } else {
            manifestConfig.expectedBridgeAddress = address(0);
        }
    }

    function getManifestConfig() public view returns (ManifestConfig memory) {
        return manifestConfig;
    }

    /// @dev Test utility — returns the subset of manifest parameters that affect the CREATE2 address.
    ///      Not used in the deployment flow itself.
    function getDeterministicConstructorArgs()
        public
        view
        returns (
            string memory name,
            string memory symbol,
            address constructorAdmin,
            uint256 constructorSupply,
            uint256 maxSupply
        )
    {
        name = manifestConfig.name;
        symbol = manifestConfig.symbol;
        constructorAdmin = manifestConfig.bootstrapAdmin;
        constructorSupply = manifestConfig.constructorSupply;
        maxSupply = manifestConfig.maxSupply;
    }
}
