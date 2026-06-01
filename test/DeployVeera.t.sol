// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployVeera} from "../script/DeployVeera.s.sol";
import {Veera} from "../src/Veera.sol";

contract DeployVeeraTest is Test {
    DeployVeera public deployer;

    // Default broadcaster address in Forge tests when vm.startBroadcast() is called without args
    address public defaultBroadcaster = 0x1804C8Ab811167987a4c4148B993c0c62CBDc549;

    function setUp() public {
        deployer = new DeployVeera();

        // Etch dummy contract bytecode to bypass extcodesize checks on admin addresses
        vm.etch(0xd2b8875b840D3BD574E1e6b440888e110632A0FD, hex"00");
        vm.etch(0xfEDB58C317d347e265990888919879a5d392a12c, hex"00");
        vm.etch(0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03, hex"00");
    }

    function test_DeployOnBaseMainnet_Success() public {
        vm.chainId(8453);

        // Run deployment. The default broadcaster (0x1804...) will deploy the contract.
        // It acts as the temporary constructor admin, mints the initial supply,
        // transfers roles to the mainnet Gnosis Safe (0xd2b8...), and revokes its own.
        (Veera token,) = deployer.run();

        address targetAdmin = 0xd2b8875b840D3BD574E1e6b440888e110632A0FD;

        // Verify supply and balance of target admin
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(targetAdmin), 1_000_000_000 ether);

        // Verify roles are granted to the target admin
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), targetAdmin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), targetAdmin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), targetAdmin));

        // Verify roles are revoked from the broadcaster
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), defaultBroadcaster));
        assertFalse(token.hasRole(token.MINTER_ROLE(), defaultBroadcaster));
        assertFalse(token.hasRole(token.PAUSER_ROLE(), defaultBroadcaster));
    }

    function test_DeployOnBSCTestnet_Success() public {
        vm.chainId(97);

        // Run deployment. The default broadcaster (0x1804...) will deploy the contract.
        // It acts as the temporary constructor admin, transfers roles to BSC Testnet admin (0x9FF0...),
        // and revokes its own. Supply should be 0.
        (Veera token,) = deployer.run();

        address targetAdmin = 0x9FF0FB8e246ac58b17Acf9b7D43B76E2D2e6Bf03;

        // Verify supply is 0
        assertEq(token.totalSupply(), 0);

        // Verify roles are granted to the target admin
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), targetAdmin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), targetAdmin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), targetAdmin));

        // Verify roles are revoked from the broadcaster
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), defaultBroadcaster));
        assertFalse(token.hasRole(token.MINTER_ROLE(), defaultBroadcaster));
        assertFalse(token.hasRole(token.PAUSER_ROLE(), defaultBroadcaster));
    }
}
