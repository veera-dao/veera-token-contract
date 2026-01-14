// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Veera Token
 * @notice Standard implementation of a Pausable, Capped, Burnable ERC20.
 * @dev Implementation details:
 * - AccessControl: Granular permissions (Admin, Minter, Pauser).
 * - ERC20Capped: Hard cap on token supply.
 * - ERC20Burnable: Supports cross-chain bridging (Burn-and-Mint).
 * - ERC20Permit: Supports gasless transactions.
 * - ERC20Pausable: Standard "freeze" logic for emergencies.
 */
contract Veera is ERC20Burnable, ERC20Capped, ERC20Pausable, ERC20Permit, AccessControl {
    // Errors
    error InvalidAdminAddress();
    error InvalidNameOrSymbol();

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(
        string memory name_,
        string memory symbol_,
        address initialAdmin,
        uint256 initialSupply,
        uint256 maxSupply_
    ) ERC20(name_, symbol_) ERC20Capped(maxSupply_) ERC20Permit(name_) {
        if (initialAdmin == address(0)) revert InvalidAdminAddress();
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert InvalidNameOrSymbol();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MINTER_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);

        if (initialSupply > 0) {
            _mint(initialAdmin, initialSupply);
        }
    }

    /**
     * @notice Mints new tokens.
     * @dev Caller must have MINTER_ROLE.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Pauses all token transfers, minting, and burning.
     * @dev Caller must have PAUSER_ROLE.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Caller must have PAUSER_ROLE.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Hook that is called before any transfer of tokens.
     * @notice Overridden to resolve inheritance conflicts and enforce logic order.
     * 1. ERC20Pausable checks paused state.
     * 2. ERC20Capped checks supply cap.
     * 3. ERC20 updates balances.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped, ERC20Pausable) {
        super._update(from, to, value);
    }
}
