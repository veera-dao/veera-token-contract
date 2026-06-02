// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LayerZeroTestHelper} from "./LayerZeroTestHelper.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oft/OFTCore.sol";
import {Veera} from "../src/Veera.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";

contract VeeraMintBurnOFTAdapterIntegrationTest is LayerZeroTestHelper {
    using OptionsBuilder for bytes;

    uint32 private constant A_EID = 1;
    uint32 private constant B_EID = 2;

    Veera public tokenA;
    VeeraMintBurnOFTAdapter public adapterA;

    Veera public tokenB;
    VeeraMintBurnOFTAdapter public adapterB;

    address public userA;
    address public userB;
    uint256 public initialBalance = 100e18;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public override {
        userA = makeAddr("userA");
        userB = makeAddr("userB");

        // Fund native fees to users
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);

        super.setUp();

        // Setup mock endpoints
        setUpEndpoints(2);

        // Chain A Setup
        tokenA = new Veera("Veera Token", "VEERA", address(this), 1000e18, 2000e18);
        adapterA = new VeeraMintBurnOFTAdapter(address(tokenA), address(endpoints[A_EID]), address(this));

        // Chain B Setup
        tokenB = new Veera("Veera Token", "VEERA", address(this), 0e18, 2000e18);
        adapterB = new VeeraMintBurnOFTAdapter(address(tokenB), address(endpoints[B_EID]), address(this));

        // Grant MINTER_ROLE to adapters
        tokenA.grantRole(MINTER_ROLE, address(adapterA));
        tokenB.grantRole(MINTER_ROLE, address(adapterB));

        // Wire Adapters
        address[] memory ofts = new address[](2);
        ofts[0] = address(adapterA);
        ofts[1] = address(adapterB);
        wireOApps(ofts);

        // Seed userA on Chain A
        tokenA.mint(userA, initialBalance);
    }

    function test_Integration_Bridge_A_To_B_Success() public {
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

        uint256 globalSupplyBefore = tokenA.totalSupply() + tokenB.totalSupply();

        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        verifyPackets(B_EID, address(adapterB));

        assertEq(tokenA.balanceOf(userA), initialBalance - amountToSend);
        assertEq(tokenB.balanceOf(userB), amountToSend);

        uint256 globalSupplyAfter = tokenA.totalSupply() + tokenB.totalSupply();
        assertEq(globalSupplyAfter, globalSupplyBefore, "Global supply must remain constant");
    }

    function test_Integration_Bridge_B_To_A_Success() public {
        // Transfer A -> B first
        uint256 amountToSend = 50e18;
        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParamAB = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory feeAB = adapterA.quoteSend(sendParamAB, false);

        vm.prank(userA);
        adapterA.send{value: feeAB.nativeFee}(sendParamAB, feeAB, payable(userA));
        verifyPackets(B_EID, address(adapterB));

        // Transfer B -> A back
        uint256 amountToSendBack = 30e18;
        vm.prank(userB);
        tokenB.approve(address(adapterB), amountToSendBack);

        SendParam memory sendParamBA = SendParam({
            dstEid: A_EID,
            to: addressToBytes32(userA),
            amountLD: amountToSendBack,
            minAmountLD: amountToSendBack,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory feeBA = adapterB.quoteSend(sendParamBA, false);

        uint256 globalSupplyBefore = tokenA.totalSupply() + tokenB.totalSupply();

        vm.prank(userB);
        adapterB.send{value: feeBA.nativeFee}(sendParamBA, feeBA, payable(userB));
        verifyPackets(A_EID, address(adapterA));

        assertEq(tokenB.balanceOf(userB), amountToSend - amountToSendBack);
        assertEq(tokenA.balanceOf(userA), (initialBalance - amountToSend) + amountToSendBack);

        uint256 globalSupplyAfter = tokenA.totalSupply() + tokenB.totalSupply();
        assertEq(globalSupplyAfter, globalSupplyBefore, "Global supply must remain constant");
    }

    function test_Integration_RevertIf_MissingMinterRole() public {
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

        // Revoke role on destination chain B
        tokenB.revokeRole(MINTER_ROLE, address(adapterB));

        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Delivery should fail as adapterB cannot mint
        vm.expectRevert();
        verifyPackets(B_EID, address(adapterB));
    }

    function test_Integration_RevertIf_SourcePaused() public {
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

        // Pause source token
        tokenA.pause();

        vm.prank(userA);
        vm.expectRevert(); // Pause blocks transfers/burns
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }

    function test_Integration_RevertIf_DestinationPaused() public {
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

        // Debit on Chain A works
        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Pause destination token B
        tokenB.pause();

        // Deliver fails because destination is paused
        vm.expectRevert();
        verifyPackets(B_EID, address(adapterB));
    }
}
