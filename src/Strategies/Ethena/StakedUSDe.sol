// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Base4626Compounder} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

interface IsUSDe {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldownShares(uint256 shares) external returns (uint256);
    function cooldownAssets(uint256 assets) external returns (uint256);
    function cooldownDuration() external view returns (uint256);
    function unstake(address receiver) external;
    function cooldowns(address) external view returns (UserCooldown memory);
}

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

    function vaultsMaxWithdraw() public view override returns (uint256) {
        if (IsUSDe(address(vault)).cooldownDuration() != 0) {
            return 0;
        } else {
            return super.vaultsMaxWithdraw();
        }
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
        uint256 _duration = IsUSDe(address(vault)).cooldownDuration();
        // If there is a cooldown
        if (_duration != 0) {
            IsUSDe.UserCooldown memory _cooldown = IsUSDe(address(vault))
                .cooldowns(address(this));

            // Check if any funds are unlocked.
            if (
                _cooldown.cooldownEnd > block.timestamp &&
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
