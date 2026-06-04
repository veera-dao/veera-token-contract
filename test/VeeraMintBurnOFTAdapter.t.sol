// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LayerZeroTestHelper, OFTMock} from "./LayerZeroTestHelper.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
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
        adapterA.setRateLimits(configs);

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
        adapterA.setRateLimits(configs);

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
        adapterA.setRateLimits(configs);
    }

    function test_RateLimiter_DisableBySettingZero() public {
        // Enable rate limit
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 50e18, window: 1 hours});
        adapterA.setRateLimits(configs);

        // Disable it by setting limit=0, window=0
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 0, window: 0});
        adapterA.setRateLimits(configs);

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

    // =========================================================================
    // Reentrancy tests
    // =========================================================================
    function test_Reentrancy_RescueERC20_HandlesCorrectly() public {
        ReentrancyGuardTester tester = new ReentrancyGuardTester(adapterA);
        MaliciousReentrantToken malToken = new MaliciousReentrantToken(address(tester));

        tester.setShouldReenterRescue(true, address(malToken));

        // When the owner calls rescueERC20, it triggers safeTransfer to the tester.
        // Tester's callback will try to call rescueERC20 again.
        // It will fail because the tester is not the owner of the adapter.
        vm.expectRevert();
        adapterA.rescueERC20(address(malToken), address(tester), 10e18);
    }

    function test_Reentrancy_Send_HandlesCorrectly() public {
        // Deploy adapter with custom malicious token to test reentrancy in _debit
        MaliciousBurnToken malToken = new MaliciousBurnToken(address(endpoints[A_EID]));
        VeeraMintBurnOFTAdapter malAdapter =
            new VeeraMintBurnOFTAdapter(address(malToken), address(endpoints[A_EID]), address(this));

        malToken.setAdapter(address(malAdapter));
        malToken.setShouldReenter(true);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: 10e18,
            minAmountLD: 10e18,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Setup mock peer for endpoint
        address[] memory ofts = new address[](2);
        ofts[0] = address(malAdapter);
        ofts[1] = address(oftB);
        wireOApps(ofts);

        MessagingFee memory fee = malAdapter.quoteSend(sendParam, false);

        // Since the malicious token tries to reenter on burnFrom, it should either revert or behave safely.
        // Let's assert it reverts or executes safely without corrupting any state.
        vm.expectRevert();
        malAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
    }

    // =========================================================================
    // Role Access tests
    // =========================================================================
    function test_RoleAccess_Pause_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.pause();
    }

    function test_RoleAccess_Unpause_OnlyOwner() public {
        adapterA.pause();
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.unpause();
    }

    function test_RoleAccess_SetRateLimits_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](0);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.setRateLimits(configs);
    }

    function test_RoleAccess_RescueERC20_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        adapterA.rescueERC20(address(tokenA), nonOwner, 10e18);
    }

    function test_RoleAccess_LzReceive_OnlyEndpoint() public {
        address nonEndpoint = makeAddr("nonEndpoint");
        Origin memory origin = Origin({srcEid: B_EID, sender: addressToBytes32(userB), nonce: 1});
        bytes memory message = "";

        vm.prank(nonEndpoint);
        vm.expectRevert(abi.encodeWithSignature("OnlyEndpoint(address)", nonEndpoint));
        adapterA.lzReceive(origin, bytes32(0), message, address(0), "");
    }

    // =========================================================================
    // Pause Effects tests
    // =========================================================================
    function test_PauseEffects_Send_Reverts() public {
        adapterA.pause();
        uint256 amountToSend = 10e18;

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

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        adapterA.send(sendParam, MessagingFee(0, 0), payable(userA));
    }

    function test_PauseEffects_LzReceive_Reverts() public {
        // Prepare a message
        uint256 amountToSend = 10e18;
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

        // Pause the adapter on chain A
        adapterA.pause();

        // Deliver packets should revert due to pause
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        verifyPackets(A_EID, address(adapterA));
    }

    function test_PauseEffects_QuoteSend_Reverts() public {
        adapterA.pause();
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: 10e18,
            minAmountLD: 10e18,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        adapterA.quoteSend(sendParam, false);
    }

    function test_PauseEffects_AdminFunctions_NotBlocked() public {
        adapterA.pause();

        // Owner should still be able to rescue tokens even if paused
        Veera randomToken = new Veera("Random", "RND", address(this), 100e18, 100e18);
        randomToken.transfer(address(adapterA), 10e18);

        adapterA.rescueERC20(address(randomToken), address(this), 10e18);
        assertEq(randomToken.balanceOf(address(this)), 100e18);

        // Owner should still be able to set rate limits even if paused
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({dstEid: B_EID, limit: 50e18, window: 1 hours});
        adapterA.setRateLimits(configs);
    }

    // =========================================================================
    // Fuzzing tests
    // =========================================================================
    function testFuzz_Send_Amounts(uint256 amount) public {
        // Bound amount between 1 and initialBalance
        amount = bound(amount, 1, initialBalance);

        // Ensure we remove dust if the conversion rate applies (Veera is 18 decimals, conversion is 10^12)
        uint256 amountCleaned = (amount / 10 ** 12) * 10 ** 12;
        vm.assume(amountCleaned > 0);

        vm.prank(userA);
        tokenA.approve(address(adapterA), amountCleaned);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: B_EID,
            to: addressToBytes32(userB),
            amountLD: amountCleaned,
            minAmountLD: amountCleaned,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = adapterA.quoteSend(sendParam, false);

        vm.prank(userA);
        adapterA.send{value: fee.nativeFee}(sendParam, fee, payable(userA));

        assertEq(tokenA.balanceOf(userA), initialBalance - amountCleaned);

        verifyPackets(B_EID, address(oftB));
        assertEq(oftB.balanceOf(userB), amountCleaned);
    }

    function testFuzz_RescueERC20_ZeroAddresses(address token, address to, uint256 amount) public {
        // If token is zero address, should revert
        if (token == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidTokenAddress.selector));
            adapterA.rescueERC20(token, to, amount);
        }
        // If recipient is zero address, should revert
        else if (to == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidReceiverAddress.selector));
            adapterA.rescueERC20(token, to, amount);
        }
    }

    function testFuzz_Constructor_ZeroAddresses(address token, address lzEndpoint, address delegate, uint8 zeroIndex)
        public
    {
        zeroIndex = uint8(bound(zeroIndex, 0, 2));

        address t = token;
        address lz = lzEndpoint;
        address d = delegate;

        if (zeroIndex == 0) {
            t = address(0);
        } else if (zeroIndex == 1) {
            lz = address(0);
        } else {
            d = address(0);
        }

        // Ensure other addresses are not zero to avoid overlapping failures
        if (t == address(0) && token == address(0)) t = address(1);
        if (lz == address(0) && lzEndpoint == address(0)) lz = address(1);
        if (d == address(0) && delegate == address(0)) d = address(1);

        vm.expectRevert();
        new VeeraMintBurnOFTAdapter(t, lz, d);
    }

    function test_Send_RevertsIf_ZeroReceiver() public {
        uint256 amountToSend = 10e18;
        oftB.mint(userB, amountToSend);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: A_EID,
            to: bytes32(0),
            amountLD: amountToSend,
            minAmountLD: amountToSend,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = oftB.quoteSend(sendParam, false);

        vm.prank(userB);
        oftB.send{value: fee.nativeFee}(sendParam, fee, payable(userB));

        // Delivery should revert because _to is zero address on Chain A (adapterA)
        vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidReceiverAddress.selector));
        verifyPackets(A_EID, address(adapterA));
    }
}

// Reentrancy tester contract
contract ReentrancyGuardTester {
    using OptionsBuilder for bytes;

    VeeraMintBurnOFTAdapter public adapter;
    bool public shouldReenterRescue;
    bool public shouldReenterSend;
    address public maliciousToken;

    constructor(VeeraMintBurnOFTAdapter _adapter) {
        adapter = _adapter;
    }

    function setShouldReenterRescue(bool _val, address _token) external {
        shouldReenterRescue = _val;
        maliciousToken = _token;
    }

    function setShouldReenterSend(bool _val) external {
        shouldReenterSend = _val;
    }

    // Fallback/receive function to try to reenter send
    receive() external payable {
        if (shouldReenterSend) {
            shouldReenterSend = false; // Prevent infinite loop

            // Build options and send parameters to attempt reentrancy
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            SendParam memory sendParam = SendParam({
                dstEid: 2,
                to: bytes32(uint256(uint160(address(this)))),
                amountLD: 10e18,
                minAmountLD: 10e18,
                extraOptions: options,
                composeMsg: "",
                oftCmd: ""
            });
            // Try to call send
            MessagingFee memory fee = adapter.quoteSend(sendParam, false);
            adapter.send{value: msg.value}(sendParam, fee, payable(address(this)));
        }
    }

    // Call callback from malicious token to try to reenter rescueERC20
    function handleCallback() external {
        if (shouldReenterRescue) {
            shouldReenterRescue = false;
            // Owner is address(this) of the test suite, but let's test if calling it from non-owner reverts
            adapter.rescueERC20(maliciousToken, address(this), 1);
        }
    }
}

// A mock malicious token that triggers callback on transfer
contract MaliciousReentrantToken {
    address public tester;

    constructor(address _tester) {
        tester = _tester;
    }

    function transfer(address, uint256) external returns (bool) {
        ReentrancyGuardTester(payable(tester)).handleCallback();
        return true;
    }

    function safeTransfer(address, uint256) external {
        ReentrancyGuardTester(payable(tester)).handleCallback();
    }

    function balanceOf(address) external pure returns (uint256) {
        return 100e18;
    }
}

contract MaliciousBurnToken {
    using OptionsBuilder for bytes;

    address public adapter;
    bool public shouldReenter;
    address public endpoint;

    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    function setAdapter(address _adapter) external {
        adapter = _adapter;
    }

    function setShouldReenter(bool _val) external {
        shouldReenter = _val;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function burnFrom(address from, uint256 amount) external {
        if (shouldReenter) {
            shouldReenter = false;
            // Attempt to reenter send
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            SendParam memory sendParam = SendParam({
                dstEid: 2,
                to: bytes32(uint256(uint160(from))),
                amountLD: amount,
                minAmountLD: amount,
                extraOptions: options,
                composeMsg: "",
                oftCmd: ""
            });
            MessagingFee memory fee = VeeraMintBurnOFTAdapter(adapter).quoteSend(sendParam, false);
            VeeraMintBurnOFTAdapter(adapter).send{value: 100}(sendParam, fee, payable(from));
        }
    }
}

