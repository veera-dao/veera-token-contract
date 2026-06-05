// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployOFTAdapter} from "../script/DeployOFTAdapter.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";
import {LayerZeroTestHelper, OFTMock} from "./LayerZeroTestHelper.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oft/OFTCore.sol";
import {Veera} from "../src/Veera.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract DeployOFTAdapterTest is Test {
    using stdJson for string;

    DeployOFTAdapter public deployer;

    function setUp() public {
        deployer = new DeployOFTAdapter();
    }

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

    function predictBridgeAddress(HelperConfig.ManifestConfig memory manifest) internal returns (address) {
        bytes memory creationCode = abi.encodePacked(
            type(VeeraMintBurnOFTAdapter).creationCode,
            abi.encode(manifest.expectedTokenAddress, manifest.lzEndpoint, manifest.targetAdmin)
        );
        bytes32 initCodeHash = keccak256(creationCode);
        return vm.computeCreate2Address(manifest.salt, initCodeHash, manifest.factory);
    }

    // test_MainnetAdapterPredictedAddressesMatch asserts mainnet addresses match (since endpoints and admin are same)
    function test_MainnetAdapterPredictedAddressesMatch() public {
        HelperConfig.ManifestConfig memory baseManifest = loadManifestConfig("deploy_manifest.mainnet.json", 8453);
        HelperConfig.ManifestConfig memory bscManifest = loadManifestConfig("deploy_manifest.mainnet.json", 56);

        address basePredicted = predictBridgeAddress(baseManifest);
        address bscPredicted = predictBridgeAddress(bscManifest);

        console.log("Base Mainnet Predicted Bridge Address: ", basePredicted);
        console.log("BSC Mainnet Predicted Bridge Address:  ", bscPredicted);

        assertEq(
            basePredicted,
            bscPredicted,
            "Mainnet adapter predicted addresses must match when endpoints and admins match"
        );
    }

    // test_TestnetAdapterPredictedAddressesMayDifferWhenAdminsDiffer asserts testnet predicted addresses differ if configs differ
    function test_TestnetAdapterPredictedAddressesMayDifferWhenAdminsDiffer() public {
        HelperConfig.ManifestConfig memory baseManifest = loadManifestConfig("deploy_manifest.testnet.json", 84532);
        HelperConfig.ManifestConfig memory bscManifest = loadManifestConfig("deploy_manifest.testnet.json", 97);

        address baseTestnetPredicted = predictBridgeAddress(baseManifest);
        address bscTestnetPredicted = predictBridgeAddress(bscManifest);

        console.log("Base Testnet Predicted Bridge Address: ", baseTestnetPredicted);
        console.log("BSC Testnet Predicted Bridge Address:  ", bscTestnetPredicted);

        bool configDiffers = (baseManifest.targetAdmin != bscManifest.targetAdmin)
            || (baseManifest.lzEndpoint != bscManifest.lzEndpoint);
        if (configDiffers) {
            assertTrue(
                baseTestnetPredicted != bscTestnetPredicted,
                "Testnet adapter predicted addresses should differ when configs differ"
            );
        } else {
            assertEq(
                baseTestnetPredicted,
                bscTestnetPredicted,
                "Testnet adapter predicted addresses should match when configs are identical"
            );
        }
    }

    // test_ChangingTargetAdminChangesBridgeAddress verifies changing targetAdmin changes predicted address
    function test_ChangingTargetAdminChangesBridgeAddress() public {
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.testnet.json", 84532);

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
        HelperConfig.ManifestConfig memory manifest = loadManifestConfig("deploy_manifest.testnet.json", 84532);

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

contract DeployOFTAdapterBehaviorTest is LayerZeroTestHelper {
    using OptionsBuilder for bytes;

    uint32 private constant A_EID = 1;
    uint32 private constant B_EID = 2;

    Veera public tokenA;
    VeeraMintBurnOFTAdapter public adapterA;
    OFTMock public oftB;

    address public userA;
    address public userB;
    uint256 public initialBalance = 100e18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public override {
        userA = makeAddr("userA");
        userB = makeAddr("userB");

        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);

        super.setUp();
        setUpEndpoints(2);

        // Chain A Setup: Deploy Veera Token and the CREATE2 Adapter
        tokenA = new Veera("Veera Token", "VEERA", address(this), 1000e18, 2000e18);
        adapterA = new VeeraMintBurnOFTAdapter(address(tokenA), address(endpoints[A_EID]), address(this));

        // Chain B Setup: Deploy OFT Mock
        oftB = new OFTMock("Veera OFT", "VEERA", address(endpoints[B_EID]), address(this));

        // Grant MINTER_ROLE to the adapter on Chain A token
        tokenA.grantRole(MINTER_ROLE, address(adapterA));

        // Wire peers
        address[] memory ofts = new address[](2);
        ofts[0] = address(adapterA);
        ofts[1] = address(oftB);
        wireOApps(ofts);

        // Mint initial tokens to userA
        tokenA.mint(userA, initialBalance);
    }

    function test_Behavior_RevertIf_UnderfundedNativeFee() public {
        uint256 amountToSend = 50e18;
        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = adapterA.quoteSend(sendParam, false);

        // Pass the correct fee in the parameter struct, but send less msg.value
        uint256 insufficientFee = fee.nativeFee / 2;

        vm.prank(userA);
        vm.expectRevert();
        adapterA.send{value: insufficientFee}(sendParam, fee, payable(userA));
    }

    function test_Behavior_RevertIf_InvalidOptionType() public {
        uint256 amountToSend = 50e18;
        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        // 1. Configure enforcedOptions on adapterA: require 200,000 gas (type 3 options)
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);
        enforcedOptions[0] =
            EnforcedOptionParam(B_EID, 1, OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0));
        adapterA.setEnforcedOptions(enforcedOptions);

        // 2. Prepare send parameters with invalid options version type 1 (hex"0001") instead of type 3
        bytes memory invalidOptions = hex"0001";
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: invalidOptions,
            composeMsg: "",
            oftCmd: ""
        });

        vm.prank(userA);
        // Expect to revert because type 1 options cannot be combined with enforced type 3 options
        vm.expectRevert();
        adapterA.quoteSend(sendParam, false);
    }

    function test_Behavior_RevertIf_InvalidDestinationEid() public {
        uint256 amountToSend = 50e18;
        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: 99999, // Unconfigured / invalid destination EID
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        vm.prank(userA);
        vm.expectRevert();
        adapterA.quoteSend(sendParam, false);
    }

    function test_Behavior_RevertIf_InsufficientAllowance() public {
        uint256 amountToSend = 50e18;
        // Do NOT approve adapterA

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = adapterA.quoteSend(sendParam, false);

        vm.prank(userA);
        vm.expectRevert();
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }

    function test_Behavior_RevertIf_InsufficientBalance() public {
        uint256 excessiveAmount = initialBalance + 1e18;
        vm.prank(userA);
        tokenA.approve(address(adapterA), excessiveAmount);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: excessiveAmount,
            minAmountLD: excessiveAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = adapterA.quoteSend(sendParam, false);

        vm.prank(userA);
        vm.expectRevert();
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }
}
