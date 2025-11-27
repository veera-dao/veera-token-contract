// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Veera is ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {
    /**
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param initialOwner Address that receives ownership controls and the initial supply.
     * @param initialSupply Initial token supply (denominated in the smallest unit).
     */
    constructor(string memory name_, string memory symbol_, address initialOwner, uint256 initialSupply)
        ERC20(name_, symbol_)
        Ownable(initialOwner)
        ERC20Permit(name_)
    {
        if (initialSupply != 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    /**
     * @notice Owner-controlled minting hook.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Pauses all token transfers.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resumes token transfers.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Enforce pause checks by using ERC20Pausable's update logic.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
