// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BaseERC20} from "../src/BaseERC20.sol";

contract BaseERC20Test is Test {
    BaseERC20 private token;

    address private constant OWNER = address(0xABCD);
    address private constant ALICE = address(0xBEEF);

    uint256 private constant INITIAL_SUPPLY = 1_000 ether;
    uint256 private constant MINT_AMOUNT = 250 ether;

    function setUp() public {
        token = new BaseERC20("Base Token", "BASE", OWNER, INITIAL_SUPPLY);
    }

    function testInitialSupplyAssignedToOwner() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(OWNER), INITIAL_SUPPLY);
        assertEq(token.owner(), OWNER);
    }

    function testOwnerCanMint() public {
        vm.prank(OWNER);
        token.mint(ALICE, MINT_AMOUNT);

        assertEq(token.balanceOf(ALICE), MINT_AMOUNT);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT);
    }

    function testNonOwnerCannotMint() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        token.mint(ALICE, MINT_AMOUNT);
    }

    function testPauseBlocksTransfers() public {
        vm.startPrank(OWNER);
        token.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(ALICE, 10 ether);
        token.unpause();
        bool success = token.transfer(ALICE, 10 ether);
        vm.stopPrank();

        assertTrue(success);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }
}
