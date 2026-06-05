// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OFTAdapter} from "@layerzerolabs/oapp-evm/contracts/oft/OFTAdapter.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oft/interfaces/IOFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Veera} from "../Veera.sol";

/**
 * @title VeeraMintBurnOFTAdapter
 * @notice LayerZero V2 OFT Adapter for Veera token using burn-on-send / mint-on-receive pattern.
 * @dev This works seamlessly with Veera's mint/burn roles.
 * - On debit (bridge out): the adapter burns tokens directly from sender via `burnFrom`.
 * - On credit (bridge in): the adapter mints tokens directly to recipient.
 * @dev Important: Only one OFTAdapter should be deployed per chain for this token. Multiple adapters break unified liquidity and can lead to permanent token loss on destination chains.
 * @dev Rate limiting: Optional outbound rate limiting per destination endpoint. Disabled by default
 *      (limit=0). The owner can enable it at any time via `setRateLimitConfigs`.
 */
contract VeeraMintBurnOFTAdapter is OFTAdapter, RateLimiter, Pausable {
    using SafeERC20 for IERC20;

    // Errors
    error InvalidTokenAddress();
    error InvalidReceiverAddress();

    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);

    function pause() external onlyOwner {
        Pausable._pause();
    }

    function unpause() external onlyOwner {
        Pausable._unpause();
    }

    /**
     * @notice Initializes the OFT Adapter with the underlying Veera token.
     * @param _token Address of the Veera ERC20 token (must not be zero).
     * @param _lzEndpoint LayerZero EndpointV2 address on this chain.
     * @param _delegate Address that will own this contract and act as delegate (recommended: Gnosis Safe).
     */
    constructor(address _token, address _lzEndpoint, address _delegate)
        OFTAdapter(_token, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}

    /**
     * @notice Sets outbound rate limits per destination endpoint.
     * @dev Only callable by the owner. Set limit=0 and window=0 to disable
     *      rate limiting for a specific destination.
     * @param _rateLimitConfigs Array of rate limit configurations.
     */
    function setRateLimits(RateLimiter.RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner {
        RateLimiter._setRateLimits(_rateLimitConfigs);
    }

    /**
     * @dev Burns tokens from the sender's balance.
     * @param _from The address to debit from.
     * @param _amountLD The amount to send (in local decimals).
     * @param _minAmountLD The minimum amount to send (in local decimals).
     * @param _dstEid The destination endpoint ID.
     * @return amountSentLD The amount sent (in local decimals).
     * @return amountReceivedLD The amount received on the destination (in local decimals).
     */
    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        whenNotPaused
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = super._debitView(_amountLD, _minAmountLD, _dstEid);

        // Rate limit check: only enforced when a limit is configured for this destination.
        // When limit == 0 (default/unconfigured), rate limiting is bypassed.
        if (RateLimiter.rateLimits[_dstEid].limit > 0) {
            RateLimiter._checkAndUpdateRateLimit(_dstEid, amountSentLD);
        }

        // Burn tokens directly from the sender's balance.
        // This requires the sender to have approved the adapter contract on the underlying token.
        Veera(address(innerToken)).burnFrom(_from, amountSentLD);

        return (amountSentLD, amountReceivedLD);
    }

    /**
     * @dev Mints tokens to the recipient's balance.
     * @param _to The address to credit to.
     * @param _amountLD The amount to mint (in local decimals).
     * @return amountReceivedLD The amount actually received (in local decimals).
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    )
        internal
        override
        whenNotPaused
        returns (uint256 amountReceivedLD)
    {
        if (_to == address(0)) revert InvalidReceiverAddress();
        // Mint the tokens directly to the recipient
        // Note: This adapter contract must be granted MINTER_ROLE on the Veera contract.
        // Note: Bridging will revert if the token is paused or if minting would exceed the supply cap.
        Veera(address(innerToken)).mint(_to, _amountLD);
        return _amountLD;
    }

    /**
     * @dev Internal function to mock the amount mutation from a OFT debit() operation.
     * @param _amountLD The amount to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @dev _dstEid The destination endpoint ID.
     * @return amountSentLD The amount sent, in local decimals.
     * @return amountReceivedLD The amount to be received on the remote chain, in local decimals.
     *
     * @dev This is where things like fees would be calculated and deducted from the amount to be received on the remote.
     */
    function _debitView(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 /*_dstEid*/
    )
        internal
        view
        virtual
        override
        whenNotPaused
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return super._debitView(_amountLD, _minAmountLD, 0);
    }

    /**
     * @notice Rescues ERC20 tokens mistakenly sent to this contract.
     * @dev Only the owner can call this. The underlying Veera token can also be rescued
     *      because this is a mint/burn adapter and the contract should never custody Veera
     *      under normal operation. Any Veera tokens present are from direct user transfers.
     * @param _token The address of the ERC20 token to rescue.
     * @param _to The address to send the rescued tokens to.
     * @param _amount The amount of tokens to rescue.
     */
    function rescueERC20(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert InvalidTokenAddress();
        if (_to == address(0)) revert InvalidReceiverAddress();
        IERC20(_token).safeTransfer(_to, _amount);
        emit ERC20Rescued(_token, _to, _amount);
    }
}
