// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

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
    function owner() external view returns (address);
    function setCooldownDuration(uint24 duration) external;
}
