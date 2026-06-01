// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, stdJson} from "forge-std/Script.sol";

uint256 constant BASE_MAINNET_CHAINID = 8453;
uint256 constant BASE_TESTNET_CHAINID = 84532; // Sepolia
uint256 constant BSC_MAINNET_CHAINID = 56;
uint256 constant BSC_TESTNET_CHAINID = 97;
uint256 constant LOCAL_CHAINID = 31337;

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
    }

    ManifestConfig public manifestConfig;

    constructor() {
        string memory path = string.concat(vm.projectRoot(), "/deploy_manifest.json");
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);

        manifestConfig.salt = json.readBytes32(".salt");
        manifestConfig.factory = json.readAddress(".factory");
        manifestConfig.factoryCodeHash = json.readBytes32(".factoryCodeHash");
        manifestConfig.bootstrapAdmin = json.readAddress(".bootstrapAdmin");
        manifestConfig.name = json.readString(".name");
        manifestConfig.symbol = json.readString(".symbol");
        manifestConfig.constructorSupply = json.readUint(".initialSupply");
        manifestConfig.maxSupply = json.readUint(".maxSupply");
        manifestConfig.expectedTokenAddress = json.readAddress(".expectedTokenAddress");

        string memory networkKey = string.concat(".networks.", vm.toString(block.chainid));
        manifestConfig.rpcIdentifier = json.readString(string.concat(networkKey, ".rpcIdentifier"));
        manifestConfig.targetAdmin = json.readAddress(string.concat(networkKey, ".targetAdmin"));
        manifestConfig.initialMintRecipient = json.readAddress(string.concat(networkKey, ".initialMintRecipient"));
        manifestConfig.expectedPostDeploymentSupply =
            json.readUint(string.concat(networkKey, ".expectedPostDeploymentSupply"));
    }

    function getManifestConfig() public view returns (ManifestConfig memory) {
        return manifestConfig;
    }

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
