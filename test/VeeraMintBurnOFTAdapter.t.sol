// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LayerZeroTestHelper, OFTMock} from "./LayerZeroTestHelper.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oft/OFTCore.sol";
import {Veera} from "../src/Veera.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";

contract VeeraMintBurnOFTAdapterTest is LayerZeroTestHelper {
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

    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public virtual override {
        userA = makeAddr("userA");
        userB = makeAddr("userB");

        // Provide native fee funding to users for bridging
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);

        super.setUp();

        // Initialize 2 endpoints using our lightweight helper
        setUpEndpoints(2);

        // Chain A: Deploy Veera token and the Adapter
        tokenA = new Veera("Veera Token", "VEERA", address(this), 1000e18, 2000e18);
        adapterA = new VeeraMintBurnOFTAdapter(address(tokenA), address(endpoints[A_EID]), address(this));

        // Chain B: Deploy OFTMock
        oftB = new OFTMock("Veera OFT", "VEERA", address(endpoints[B_EID]), address(this));

        // Grant MINTER_ROLE to the adapter on Chain A token
        tokenA.grantRole(MINTER_ROLE, address(adapterA));

        // Wire the adapter on Chain A to the OFT on Chain B
        address[] memory ofts = new address[](2);
        ofts[0] = address(adapterA);
        ofts[1] = address(oftB);
        this.wireOApps(ofts);

        // Mint initial tokens to userA on Chain A
        tokenA.mint(userA, initialBalance);
    }

    function test_Initialization() public view {
        assertEq(address(adapterA.token()), address(tokenA));
        assertEq(adapterA.owner(), address(this));
        assertTrue(tokenA.hasRole(MINTER_ROLE, address(adapterA)));
    }

    function test_Send_OFTAdapter_To_OFT_Success() public {
        uint256 amountToSend = 50e18;

        // User A approves the adapter to spend their tokens on Chain A
        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        // Build options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Prepare send parameters
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the native fee
        MessagingFee memory fee = adapterA.quoteSend(sendParam, false);

        uint256 initialTotalSupplyA = tokenA.totalSupply();

        // Perform the send operation
        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Assert tokens are burned on Chain A
        assertEq(tokenA.balanceOf(userA), initialBalance - amountToSend);
        assertEq(tokenA.totalSupply(), initialTotalSupplyA - amountToSend);

        // Deliver message to Chain B
        verifyPackets(B_EID, address(oftB));

        // Assert tokens are minted on Chain B
        assertEq(oftB.balanceOf(userB), amountToSend);
    }

    function test_Send_OFT_To_OFTAdapter_Success() public {
        uint256 amountToSend = 40e18;

        // Mint some tokens to userB on Chain B first
        oftB.mint(userB, amountToSend);
        assertEq(oftB.balanceOf(userB), amountToSend);

        // Build options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Prepare send parameters
        SendParam memory sendParam = SendParam({
            dstEid: A_EID,
            to: addressToBytes32(userA),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee on Chain B
        MessagingFee memory fee = oftB.quoteSend(sendParam, false);

        uint256 initialBalanceA = tokenA.balanceOf(userA);
        uint256 initialTotalSupplyA = tokenA.totalSupply();

        // Perform send on Chain B (OFTMock does not require approval because approvalRequired is false)
        vm.prank(userB);
        oftB.send{value: fee.nativeFee}(sendParam, fee, payable(userB));

        // Assert tokens are burned on Chain B
        assertEq(oftB.balanceOf(userB), 0);

        // Deliver message to Chain A
        verifyPackets(A_EID, address(adapterA));

        // Assert tokens are minted on Chain A
        assertEq(tokenA.balanceOf(userA), initialBalanceA + amountToSend);
        assertEq(tokenA.totalSupply(), initialTotalSupplyA + amountToSend);
    }

    function test_Debit_RevertsIf_NoAllowance() public {
        uint256 amountToSend = 50e18;
        // User A does NOT approve the adapter

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
        vm.expectRevert(); // Should revert due to ERC20InsufficientAllowance or similar
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }

    function test_Debit_RevertsIf_SlippageExceeded() public {
        uint256 amountToSend = 50e18;

        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Prepare valid parameters to get a quote first
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

        // Now set minAmountLD higher than amountLD to trigger revert during send
        sendParam.minAmountLD = 60e18;

        vm.prank(userA);
        vm.expectRevert(); // Reverts due to SlippageExceeded / minAmountLD validation
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }

    function test_Credit_RevertsIf_NoMinterRole() public {
        uint256 amountToSend = 40e18;
        oftB.mint(userB, amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: A_EID,
            to: addressToBytes32(userA),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = oftB.quoteSend(sendParam, false);

        vm.prank(userB);
        oftB.send{value: fee.nativeFee}(sendParam, fee, payable(userB));

        // Revoke the minter role from the adapter
        tokenA.revokeRole(MINTER_ROLE, address(adapterA));

        // Attempting to deliver the packets to Chain A should fail/revert because the adapter lacks MINTER_ROLE
        vm.expectRevert();
        verifyPackets(A_EID, address(adapterA));
    }

    function test_BridgeRespectsPause() public {
        uint256 amountToSend = 50e18;

        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        // Pause the token on Chain A
        tokenA.pause();

        // 1. Send from Chain A should revert when token is paused
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParamA = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory feeA = adapterA.quoteSend(sendParamA, false);

        vm.prank(userA);
        vm.expectRevert(); // Reverts due to paused token
        adapterA.send{value: feeA.nativeFee}(sendParamA, feeA, payable(userA));

        // Unpause to clear the state and send from Chain B to Chain A
        tokenA.unpause();

        // Mint and send from Chain B
        oftB.mint(userB, amountToSend);

        SendParam memory sendParamB = SendParam({
            dstEid: A_EID,
            to: addressToBytes32(userA),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory feeB = oftB.quoteSend(sendParamB, false);

        vm.prank(userB);
        oftB.send{value: feeB.nativeFee}(sendParamB, feeB, payable(userB));

        // Pause the token again before packet delivery (credit) on Chain A
        tokenA.pause();

        // 2. Delivery to Chain A should fail because token is paused (minting is blocked)
        vm.expectRevert();
        verifyPackets(A_EID, address(adapterA));
    }

    function test_RescueERC20_Success() public {
        // Deploy a dummy ERC20 token to rescue
        Veera randomToken = new Veera("Random Token", "RAND", address(this), 1000e18, 1000e18);

        // Mistakenly transfer 100 random tokens to the adapter
        assertTrue(randomToken.transfer(address(adapterA), 100e18));
        assertEq(randomToken.balanceOf(address(adapterA)), 100e18);

        address recipient = makeAddr("recipient");

        // Expect the ERC20Rescued event to be emitted
        vm.expectEmit(true, true, false, true);
        emit ERC20Rescued(address(randomToken), recipient, 100e18);

        // Rescue the tokens as owner
        adapterA.rescueERC20(address(randomToken), recipient, 100e18);

        // Verify balances
        assertEq(randomToken.balanceOf(address(adapterA)), 0);
        assertEq(randomToken.balanceOf(recipient), 100e18);
    }

    function test_RescueUnderlyingVeera_DirectTransferOnly() public {
        // Mint some tokens to this contract and transfer to adapter (simulating direct transfer by user error)
        uint256 amountToRescue = 100e18;
        tokenA.mint(address(this), amountToRescue);
        assertTrue(tokenA.transfer(address(adapterA), amountToRescue));

        assertEq(tokenA.balanceOf(address(adapterA)), amountToRescue);

        address recipient = makeAddr("rescueRecipient");

        // Rescue the underlying Veera tokens as owner
        adapterA.rescueERC20(address(tokenA), recipient, amountToRescue);

        // Verify balances
        assertEq(tokenA.balanceOf(address(adapterA)), 0);
        assertEq(tokenA.balanceOf(recipient), amountToRescue);
    }

    function test_RescueERC20_RevertsIf_NonOwner() public {
        Veera randomToken = new Veera("Random Token", "RAND", address(this), 1000e18, 1000e18);
        assertTrue(randomToken.transfer(address(adapterA), 100e18));

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.rescueERC20(address(randomToken), nonOwner, 100e18);
    }

    function test_RescueERC20_RevertsIf_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidTokenAddress.selector));
        adapterA.rescueERC20(address(0), userA, 100e18);

        vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidReceiverAddress.selector));
        adapterA.rescueERC20(address(tokenA), address(0), 100e18);
    }

    function test_Constructor_RevertsIf_ZeroTokenAddress() public {
        vm.expectRevert();
        new VeeraMintBurnOFTAdapter(address(0), address(endpoints[A_EID]), address(this));
    }

    function test_Constructor_RevertsIf_ZeroEndpointAddress() public {
        vm.expectRevert();
        new VeeraMintBurnOFTAdapter(address(tokenA), address(0), address(this));
    }

    function test_Constructor_RevertsIf_ZeroDelegateAddress() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new VeeraMintBurnOFTAdapter(address(tokenA), address(endpoints[A_EID]), address(0));
    }

    // =========================================================================
    // Rate Limiter Tests
    // =========================================================================

    function test_RateLimiter_DefaultOff() public {
        // With no rate limit configured, transfers should work normally
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

        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Should succeed without any rate limit configured
        assertEq(tokenA.balanceOf(userA), initialBalance - amountToSend);
    }

    function test_RateLimiter_EnforcesLimit() public {
        // Set a rate limit: 50e18 per 1 hour for destination B_EID
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 50e18, window: 1 hours});
        adapterA.setRateLimitConfigs(configs);

        // First send of 50e18 should succeed (exactly at limit)
        uint256 amountToSend = 50e18;

        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend * 2);

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
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Second send should revert (rate limit exceeded)
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }

    function test_RateLimiter_WindowDecay() public {
        // Set rate limit: 50e18 per 1 hour
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 50e18, window: 1 hours});
        adapterA.setRateLimitConfigs(configs);

        uint256 amountToSend = 50e18;

        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend * 2);

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

        // First send consumes entire limit
        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Advance time past the window
        vm.warp(block.timestamp + 1 hours + 1);

        // Mint more tokens to userA for the second send
        tokenA.mint(userA, amountToSend);
        vm.prank(userA);
        tokenA.approve(address(adapterA), amountToSend);

        // Should succeed again after window expires
        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
    }

    function test_RateLimiter_OnlyOwner() public {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 50e18, window: 1 hours});

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.setRateLimitConfigs(configs);
    }

    function test_RateLimiter_DisableBySettingZero() public {
        // Enable rate limit
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 50e18, window: 1 hours});
        adapterA.setRateLimitConfigs(configs);

        // Disable it by setting limit=0, window=0
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 0, window: 0});
        adapterA.setRateLimitConfigs(configs);

        // Should be able to send any amount now
        uint256 amountToSend = 90e18;

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

        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        assertEq(tokenA.balanceOf(userA), initialBalance - amountToSend);
    }

    // =========================================================================
    // Pausable Tests
    // =========================================================================

    function test_Adapter_Pause_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        // 1. Non-owner calling pause() reverts
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.pause();

        // 2. Non-owner calling unpause() reverts
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.unpause();

        // 3. Owner calling pause() succeeds
        assertFalse(adapterA.paused());
        adapterA.pause();
        assertTrue(adapterA.paused());

        // 4. Owner calling unpause() succeeds
        adapterA.unpause();
        assertFalse(adapterA.paused());
    }

    function test_Adapter_Pause_BlocksSend() public {
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

        // Pause the adapter
        adapterA.pause();

        // Send should fail with EnforcedPause
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        // Unpause the adapter
        adapterA.unpause();

        // Send should succeed now
        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));
        assertEq(tokenA.balanceOf(userA), initialBalance - amountToSend);
    }

    function test_Adapter_Pause_BlocksQuoteSend() public {
        uint256 amountToSend = 50e18;

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

        // Pause the adapter
        adapterA.pause();

        // quoteSend should fail with EnforcedPause
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        adapterA.quoteSend(sendParam, false);

        // Unpause the adapter
        adapterA.unpause();

        // quoteSend should succeed now
        MessagingFee memory fee = adapterA.quoteSend(sendParam, false);
        assertTrue(fee.nativeFee > 0);
    }

    function test_Adapter_Pause_BlocksCredit() public {
        uint256 amountToSend = 40e18;

        // Mint and send from Chain B to Chain A
        oftB.mint(userB, amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: A_EID,
            to: addressToBytes32(userA),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = oftB.quoteSend(sendParam, false);

        vm.prank(userB);
        oftB.send{value: fee.nativeFee}(sendParam, fee, payable(userB));

        // Pause the adapter on Chain A before packet delivery
        adapterA.pause();

        // Packet delivery (credit) should revert on Chain A due to pause
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        this.verifyPackets(A_EID, address(adapterA));

        // Unpause the adapter
        adapterA.unpause();

        // Delivery should now succeed
        verifyPackets(A_EID, address(adapterA));
        assertEq(tokenA.balanceOf(userA), initialBalance + amountToSend);
    }
}
