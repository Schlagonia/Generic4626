// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Base4626Compounder} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

import {IsUSDe} from "../../interfaces/IsUSDe.sol";

contract StakedUSDe is Base4626Compounder, AuctionSwapper {
    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    mapping(address => uint256) public minAmountToSellMapping;

    constructor()
        Base4626Compounder(
            0x4c9EDD5852cd905f086C759E8383e09bff1E68B3,
            "sUSDe Staker",
            0x9D39A5DE30e57443BfF2A8307A4256c8797A3497
        )
    {}

    function startCooldown(
        uint256 _assetAmount
    ) external onlyEmergencyAuthorized returns (uint256) {
        return IsUSDe(address(vault)).cooldownAssets(_assetAmount);
    }

    function cooldownAll() external onlyEmergencyAuthorized returns (uint256) {
        return IsUSDe(address(vault)).cooldownShares(balanceOfVault());
    }

    function unstake() external onlyEmergencyAuthorized {
        IsUSDe(address(vault)).unstake(address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        if (IsUSDe(address(vault)).cooldownDuration() != 0) {
            // We should only reach this if everything is cooled down.
            IsUSDe(address(vault)).unstake(address(this));
        } else {
            super._freeFunds(_amount);
        }
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // If there is a cooldown return what has been fully cooled down
        if (IsUSDe(address(vault)).cooldownDuration() != 0) {
            IsUSDe.UserCooldown memory _cooldown = IsUSDe(address(vault))
                .cooldowns(address(this));

            // Check if the funds are unlocked.
            if (_cooldown.cooldownEnd <= block.timestamp) {
                return _cooldown.underlyingAmount;
            }
        } else {
            return super.vaultsMaxWithdraw();
        }
    }

    function valueOfVault() public view override returns (uint256) {
        // Vault balance plus anything cooling down.
        return
            vault.convertToAssets(balanceOfVault()) +
            IsUSDe(address(vault)).cooldowns(address(this)).underlyingAmount;
    }

    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            require(Auction(_auction).want() == address(asset), "wrong want");
        }
        auction = _auction;
    }

    function _auctionKicked(
        address _token
    ) internal virtual override returns (uint256 _kicked) {
        require(
            _token != address(asset) && _token != address(vault),
            "!allowed"
        );
        _kicked = super._auctionKicked(_token);
        require(_kicked >= minAmountToSellMapping[_token], "too little");
    }

    /**
     * @notice Set the `minAmountToSellMapping` for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _claimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is to low, amounts
     * are to low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _amount Min required amount to sell.
     */
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external onlyManagement {
        minAmountToSellMapping[_token] = _amount;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        // If there is a cooldown
        if (IsUSDe(address(vault)).cooldownDuration() != 0) {
            IsUSDe.UserCooldown memory _cooldown = IsUSDe(address(vault))
                .cooldowns(address(this));

            // Check if any funds are unlocked.
            if (
                _cooldown.cooldownEnd <= block.timestamp &&
                _cooldown.underlyingAmount != 0
            ) {
                IsUSDe(address(vault)).unstake(address(this));
            }

            // Start the cooldown
            IsUSDe(address(vault)).cooldownShares(balanceOfVault());
        } else {
            super._emergencyWithdraw(_amount);
        }
    }
}
