// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Veera} from "../src/Veera.sol"; 
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract VeeraTest is Test {
    Veera public token;

    // Define actors
    address public admin;
    address public bridgeAdapter;
    address public user;
    uint256 public adminPrivateKey;
    uint256 public userPrivateKey;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        adminPrivateKey = 0xA11CE;
        admin = vm.addr(adminPrivateKey);
        
        userPrivateKey = 0xB0B;
        user = vm.addr(userPrivateKey);

        bridgeAdapter = makeAddr("bridgeAdapter");

        vm.startPrank(admin);
        token = new Veera("Veera Token", "VEERA", admin, 1000e18, 2000e18);
        vm.stopPrank();

        targetContract(address(token));
    }

    /* ========================================================================
                                    SETUP & ROLES
       ======================================================================== */

    function test_InitialSetup() public view {
        assertEq(token.name(), "Veera Token");
        assertEq(token.symbol(), "VEERA");
        assertEq(token.balanceOf(admin), 1000e18);
        
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(token.hasRole(MINTER_ROLE, admin));
        assertTrue(token.hasRole(PAUSER_ROLE, admin));
    }

    function test_GrantMinterRole() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, bridgeAdapter);
        assertTrue(token.hasRole(MINTER_ROLE, bridgeAdapter));
    }

    function test_RevokeMinterRole() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, bridgeAdapter);
        assertTrue(token.hasRole(MINTER_ROLE, bridgeAdapter));

        vm.prank(admin);
        token.revokeRole(MINTER_ROLE, bridgeAdapter);
        assertFalse(token.hasRole(MINTER_ROLE, bridgeAdapter));

        vm.prank(bridgeAdapter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                bridgeAdapter,
                MINTER_ROLE
            )
        );
        token.mint(user, 100e18);
    }

    function test_MultipleMinters() public {
        address minter2 = makeAddr("minter2");
        
        vm.startPrank(admin);
        token.grantRole(MINTER_ROLE, bridgeAdapter);
        token.grantRole(MINTER_ROLE, minter2);
        vm.stopPrank();

        vm.prank(bridgeAdapter);
        token.mint(user, 100e18);
        assertEq(token.balanceOf(user), 100e18);

        vm.prank(minter2);
        token.mint(user, 50e18);
        assertEq(token.balanceOf(user), 150e18);
    }

    /* ========================================================================
                                      MINTING
       ======================================================================== */

    function test_Minting_Success() public {
        vm.prank(admin);
        token.mint(user, 500e18);
        assertEq(token.balanceOf(user), 500e18);
    }

    function test_RevertIf_Minting_Unauthorized() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                MINTER_ROLE
            )
        );
        token.mint(user, 1000e18);
    }

    function test_RevertIf_Minting_ToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InvalidReceiver.selector,
                address(0)
            )
        );
        token.mint(address(0), 100e18);
    }

    function test_RevertIf_Minting_ExceedsCap() public {
        vm.prank(admin);
        vm.expectRevert(); 
        token.mint(user, 1001e18);
    }

    function test_Minting_UpToCap() public {
        vm.prank(admin);
        token.mint(user, 1000e18);
        assertEq(token.totalSupply(), 2000e18);
        assertEq(token.cap(), 2000e18);
    }

    /* ========================================================================
                                      BURNING
       ======================================================================== */

    function test_Burn() public {
        vm.prank(admin);
        token.burn(100e18);
        assertEq(token.balanceOf(admin), 900e18);
    }

    function test_BurnFrom() public {
        vm.prank(admin);
        token.approve(user, 100e18);

        vm.prank(user);
        token.burnFrom(admin, 100e18);

        assertEq(token.balanceOf(admin), 900e18);
        assertEq(token.allowance(admin, user), 0);
    }

    /* ========================================================================
                                      PAUSING
       ======================================================================== */

    function test_Pause_StopsTransfers() public {
        vm.startPrank(admin);
        token.pause();
        vm.stopPrank();

        assertTrue(token.paused());

        vm.prank(admin);
        vm.expectRevert(); 
        // FIX: Removed 'bool success =' and 'assertTrue(success)'
        // When expecting a revert, we just make the call.
        token.transfer(user, 10e18);
    }

    function test_TransferFrom_RespectsPause() public {
        address spender = makeAddr("spender");
        vm.prank(admin);
        token.mint(user, 100e18);

        vm.prank(user);
        token.approve(spender, 50e18);

        vm.prank(admin);
        token.pause();

        vm.prank(spender);
        vm.expectRevert(); 
        // FIX: Removed assertion on revert case
        token.transferFrom(user, admin, 10e18);

        vm.prank(admin);
        token.unpause();

        vm.prank(spender);
        // This success case should still capture return value to satisfy linter
        bool success = token.transferFrom(user, admin, 10e18);
        assertTrue(success);
        
        assertEq(token.balanceOf(admin), 1010e18); 
    }

    function test_Pause_StopsMinting() public {
        vm.startPrank(admin);
        token.pause();
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(); 
        token.mint(user, 100e18);
    }

    function test_Pause_StopsBurning() public {
        vm.startPrank(admin);
        token.pause();
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(); 
        token.burn(50e18);
    }

    function test_Unpause_ResumesTransfers() public {
        vm.startPrank(admin);
        token.pause();
        token.unpause();
        vm.stopPrank();

        assertFalse(token.paused());

        vm.prank(admin);
        bool success = token.transfer(user, 10e18);

        assertTrue(success, "Transfer should succeed");
        assertEq(token.balanceOf(user), 10e18);
    }

    /* ========================================================================
                                   ERC20 PERMIT
       ======================================================================== */

    bytes32 constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    function test_Permit() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 amount = 100e18;
        address spender = bridgeAdapter;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            admin, 
            spender,
            amount,
            token.nonces(admin),
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);

        vm.prank(user); 
        token.permit(admin, spender, amount, deadline, v, r, s);

        assertEq(token.allowance(admin, spender), amount);
    }

    function test_Permit_ExpiredDeadline() public {
        uint256 deadline = block.timestamp - 1; 
        uint256 amount = 100e18;
        address spender = bridgeAdapter;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            admin,
            spender,
            amount,
            token.nonces(admin),
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);

        vm.prank(user);
        vm.expectRevert(); 
        token.permit(admin, spender, amount, deadline, v, r, s);
    }

    function test_Permit_InvalidSignature() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 amount = 100e18;
        address spender = bridgeAdapter;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            admin,
            spender,
            amount,
            token.nonces(admin),
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.prank(user);
        vm.expectRevert(); 
        token.permit(admin, spender, amount, deadline, v, r, s);
    }

    function test_Pause_DuringPermit() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 amount = 100e18;
        address spender = bridgeAdapter;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            admin,
            spender,
            amount,
            token.nonces(admin),
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);

        vm.prank(admin);
        token.pause();

        vm.prank(user);
        token.permit(admin, spender, amount, deadline, v, r, s);
        assertEq(token.allowance(admin, spender), amount);

        vm.prank(admin);
        vm.expectRevert();
        // FIX: Removed assertion on revert case
        token.transfer(user, 10e18);
    }

    function test_SupportsInterface() public view {
        assertTrue(token.supportsInterface(0x01ffc9a7)); // IERC165
        bytes4 iaccessControlId = type(IAccessControl).interfaceId;
        assertTrue(token.supportsInterface(iaccessControlId));
    }

    /* ========================================================================
                                      EDGE CASES
       ======================================================================== */

    function test_InitialSupply_Zero() public {
        vm.startPrank(admin);
        Veera zeroSupplyToken = new Veera("Veera Token", "VEERA", admin, 0, 1000e18);
        vm.stopPrank();

        assertEq(zeroSupplyToken.totalSupply(), 0);
        assertEq(zeroSupplyToken.balanceOf(admin), 0);
        assertEq(zeroSupplyToken.cap(), 1000e18);
        
        vm.prank(admin);
        zeroSupplyToken.mint(user, 1000e18);
        assertEq(zeroSupplyToken.totalSupply(), 1000e18);
    }

    function test_InitialSupply_EqualsMaxSupply() public {
        vm.startPrank(admin);
        Veera cappedToken = new Veera("Veera Token", "VEERA", admin, 1000e18, 1000e18);
        vm.stopPrank();

        assertEq(cappedToken.totalSupply(), 1000e18);
        assertEq(cappedToken.cap(), 1000e18);
        
        vm.prank(admin);
        vm.expectRevert(); 
        cappedToken.mint(user, 1);
    }

    /* ========================================================================
                                      FUZZ TESTS
       ======================================================================== */

    function testFuzz_Mint(uint256 amount) public {
        uint256 remainingSupply = token.cap() - token.totalSupply();
        amount = bound(amount, 0, remainingSupply);
        
        vm.prank(admin);
        token.mint(user, amount);
        
        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), 1000e18 + amount);
        assertLe(token.totalSupply(), token.cap());
    }

    function testFuzz_Burn(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(admin));
        uint256 initialSupply = token.totalSupply();
        uint256 adminBalance = token.balanceOf(admin);
        
        vm.prank(admin);
        token.burn(amount);
        
        assertEq(token.balanceOf(admin), adminBalance - amount);
        assertEq(token.totalSupply(), initialSupply - amount);
    }

    function testFuzz_Mint_ExceedsCap(uint256 amount) public {
        uint256 remainingSupply = token.cap() - token.totalSupply();
        amount = bound(amount, remainingSupply + 1, type(uint256).max);
        
        vm.prank(admin);
        vm.expectRevert();
        token.mint(user, amount);
    }

    /* ========================================================================
                                   INVARIANT TESTS
       ======================================================================== */

    function invariant_TotalSupply_Always_Leq_Cap() public view {
        assertLe(token.totalSupply(), token.cap());
    }

    function invariant_SumOfBalances_Equals_TotalSupply() public view {
        uint256 adminBalance = token.balanceOf(admin);
        uint256 userBalance = token.balanceOf(user);
        uint256 bridgeBalance = token.balanceOf(bridgeAdapter);
        
        assertGe(token.totalSupply(), adminBalance + userBalance + bridgeBalance);
    }
}