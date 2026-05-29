// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Veera} from "../src/Veera.sol";
import {VeeraMintBurnOFTAdapter} from "../src/bridge/VeeraMintBurnOFTAdapter.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title VeeraMintBurnOFTAdapterHarness
 * @notice Exposes the internal _debit and _credit functions of the adapter for isolated unit testing.
 */
contract VeeraMintBurnOFTAdapterHarness is VeeraMintBurnOFTAdapter {
    constructor(address _token, address _lzEndpoint, address _delegate)
        VeeraMintBurnOFTAdapter(_token, _lzEndpoint, _delegate)
    {}

    function exposedDebit(address _from, uint256 _amountLd, uint256 _minAmountLd, uint32 _dstEid)
        external
        returns (uint256 amountSentLd, uint256 amountReceivedLd)
    {
        return _debit(_from, _amountLd, _minAmountLd, _dstEid);
    }

    function exposedCredit(address _to, uint256 _amountLd, uint32 _srcEid) external returns (uint256 amountReceivedLd) {
        return _credit(_to, _amountLd, _srcEid);
    }
}

contract MockLayerZeroEndpoint {
    function setDelegate(
        address /*_delegate*/
    )
        external {
        // Mock success for constructor setup
    }
}

contract VeeraMintBurnOFTAdapterTest is Test {
    Veera public token;
    VeeraMintBurnOFTAdapterHarness public adapter;

    address public admin;
    address public user;
    address public mockLzEndpoint;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");

        // Deploy the mock LayerZero Endpoint
        MockLayerZeroEndpoint mockEndpoint = new MockLayerZeroEndpoint();
        mockLzEndpoint = address(mockEndpoint);

        vm.startPrank(admin);
        // Deploy Veera: Name, Symbol, Admin, Initial Supply, Max Supply
        token = new Veera("Veera Token", "VEERA", admin, 1000e18, 2000e18);

        // Deploy testing harness
        adapter = new VeeraMintBurnOFTAdapterHarness(address(token), mockLzEndpoint, admin);

        // Grant MINTER_ROLE to the adapter
        token.grantRole(MINTER_ROLE, address(adapter));
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(address(adapter.token()), address(token));
        assertEq(adapter.owner(), admin);
        assertTrue(token.hasRole(MINTER_ROLE, address(adapter)));
    }

    function test_Debit_BurnsTokens_Success() public {
        // Prepare: Mint 100 tokens to user
        vm.prank(admin);
        token.mint(user, 100e18);
        assertEq(token.balanceOf(user), 100e18);
        uint256 initialTotalSupply = token.totalSupply();

        // User approves adapter
        vm.prank(user);
        token.approve(address(adapter), 50e18);

        // Debit: Burn 50 tokens
        vm.prank(address(mockLzEndpoint));
        (uint256 amountSent, uint256 amountReceived) = adapter.exposedDebit(user, 50e18, 50e18, 1);

        assertEq(amountSent, 50e18);
        assertEq(amountReceived, 50e18);

        // Verify balances and supply
        assertEq(token.balanceOf(user), 50e18);
        assertEq(token.totalSupply(), initialTotalSupply - 50e18);
        assertEq(token.balanceOf(address(adapter)), 0); // No tokens locked in the adapter
    }

    function test_Debit_RevertsIf_NoAllowance() public {
        // Prepare: Mint 100 tokens to user
        vm.prank(admin);
        token.mint(user, 100e18);

        // Debit without approval: should revert
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert();
        adapter.exposedDebit(user, 50e18, 50e18, 1);
    }

    function test_Debit_RevertsIf_SlippageExceeded() public {
        // Prepare: Mint 100 tokens to user
        vm.prank(admin);
        token.mint(user, 100e18);

        vm.prank(user);
        token.approve(address(adapter), 50e18);

        // Debit: request minAmount of 60e18 for a 50e18 send (should revert with SlippageExceeded)
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert();
        adapter.exposedDebit(user, 50e18, 60e18, 1);
    }

    function test_Credit_MintsTokens_Success() public {
        uint256 initialTotalSupply = token.totalSupply();

        // Credit: Mint 75 tokens to user
        vm.prank(address(mockLzEndpoint));
        uint256 amountReceived = adapter.exposedCredit(user, 75e18, 1);

        assertEq(amountReceived, 75e18);

        // Verify balances and supply
        assertEq(token.balanceOf(user), 75e18);
        assertEq(token.totalSupply(), initialTotalSupply + 75e18);
    }

    function test_Credit_RevertsIf_NoMinterRole() public {
        // Deploy a new adapter and do NOT grant it MINTER_ROLE
        vm.prank(admin);
        VeeraMintBurnOFTAdapterHarness unauthorizedAdapter =
            new VeeraMintBurnOFTAdapterHarness(address(token), mockLzEndpoint, admin);

        // Credit should revert
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(unauthorizedAdapter), MINTER_ROLE
            )
        );
        unauthorizedAdapter.exposedCredit(user, 75e18, 1);
    }

    function test_Credit_RevertsIf_ZeroReceiverAddress() public {
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidReceiverAddress.selector));
        adapter.exposedCredit(address(0), 75e18, 1);
    }

    function test_BridgeRespectsPause() public {
        // Prepare: Mint tokens and approve
        vm.prank(admin);
        token.mint(user, 100e18);

        vm.prank(user);
        token.approve(address(adapter), 100e18);

        // Admin pauses the token
        vm.prank(admin);
        token.pause();

        // Debit (burn) should revert when paused
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert();
        adapter.exposedDebit(user, 50e18, 50e18, 1);

        // Credit (mint) should revert when paused
        vm.prank(address(mockLzEndpoint));
        vm.expectRevert();
        adapter.exposedCredit(user, 50e18, 1);

        // Admin unpauses the token
        vm.prank(admin);
        token.unpause();

        // Operations should now succeed
        vm.prank(address(mockLzEndpoint));
        adapter.exposedDebit(user, 50e18, 50e18, 1);
        assertEq(token.balanceOf(user), 50e18);

        vm.prank(address(mockLzEndpoint));
        adapter.exposedCredit(user, 25e18, 1);
        assertEq(token.balanceOf(user), 75e18);
    }

    function test_RescueERC20_Success() public {
        // Deploy a dummy ERC20 token to rescue
        vm.prank(admin);
        Veera randomToken = new Veera("Random Token", "RAND", admin, 1000e18, 1000e18);

        // Mistakenly transfer 100 random tokens to the adapter
        vm.prank(admin);
        assertTrue(randomToken.transfer(address(adapter), 100e18));
        assertEq(randomToken.balanceOf(address(adapter)), 100e18);

        address recipient = makeAddr("recipient");

        // Expect the ERC20Rescued event to be emitted
        vm.expectEmit(true, true, false, true);
        emit ERC20Rescued(address(randomToken), recipient, 100e18);

        // Rescue the tokens as owner
        vm.prank(admin);
        adapter.rescueERC20(address(randomToken), recipient, 100e18);

        // Verify balances
        assertEq(randomToken.balanceOf(address(adapter)), 0);
        assertEq(randomToken.balanceOf(recipient), 100e18);
    }

    function test_RescueERC20_RevertsIf_NonOwner() public {
        vm.prank(admin);
        Veera randomToken = new Veera("Random Token", "RAND", admin, 1000e18, 1000e18);

        vm.prank(admin);
        assertTrue(randomToken.transfer(address(adapter), 100e18));

        // Try to rescue as non-owner (user)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        adapter.rescueERC20(address(randomToken), user, 100e18);
    }

    function test_RescueERC20_RevertsIf_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidTokenAddress.selector));
        adapter.rescueERC20(address(0), user, 100e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VeeraMintBurnOFTAdapter.InvalidReceiverAddress.selector));
        adapter.rescueERC20(address(token), address(0), 100e18);
    }

    function test_Constructor_RevertsIf_ZeroTokenAddress() public {
        vm.prank(admin);
        // Expect revert due to decimals() call on address(0) in base constructor
        vm.expectRevert();
        new VeeraMintBurnOFTAdapterHarness(address(0), mockLzEndpoint, admin);
    }

    function test_Constructor_RevertsIf_ZeroEndpointAddress() public {
        vm.prank(admin);
        // Expect revert due to endpoint check or low-level call to address(0) in base constructor
        vm.expectRevert();
        new VeeraMintBurnOFTAdapterHarness(address(token), address(0), admin);
    }

    function test_Constructor_RevertsIf_ZeroDelegateAddress() public {
        vm.prank(admin);
        // Expect revert from Ownable(0) constructor which executes first
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new VeeraMintBurnOFTAdapterHarness(address(token), mockLzEndpoint, address(0));
    }
}
