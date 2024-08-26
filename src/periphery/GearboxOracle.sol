// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

import "forge-std/console2.sol"; // @todo: remove all logs

// example of FE APY calcs: https://github.com/Gearbox-protocol/sdk/blob/next/src/gearboxRewards/apy.ts
// https://github.com/Gearbox-protocol/defillama/blob/7127e015b2dc3f47043292e8801d01930560003c/src/yield-server/index.ts#L242

interface IStrategy {
    function vault() external view returns (address);
    function staking() external view returns (address);
    function asset() external view returns (address);
}

interface IVault {
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function expectedLiquidity() external view returns (uint256);
    function baseInterestRate() external view returns (uint256);
    function totalBorrowed() external view returns (uint256);
    function quotaRevenue() external view returns (uint256);
    function withdrawFee() external view returns (uint256);
    function supplyRate() external view returns (uint256);
}

interface IStaking {
    function totalSupply() external view returns (uint256);
    function farmInfo() external view returns (uint40, uint32, uint184, uint256);
}

interface ICurvePool {
    function price_oracle() external view returns (uint256);
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
}


interface IUniswapRouter {
    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);
}

contract GearboxOracle {

    // Curve pool for GEAR pricing
    address internal constant GEAR_ETH_CURVE_POOL = 0x0E9B5B092caD6F1c5E6bc7f89Ffe1abb5c95F1C2;

    // Tokens
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Gearbox constants
    uint256 internal constant RAY = 1e27;
    uint16 internal constant PERCENTAGE_FACTOR = 1e4;
    uint256 internal constant SECONDS_PER_YEAR = 31536000;

    /**
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(address _strategy, int256 _delta) external view returns (uint256) {
        IVault vault = IVault(IStrategy(_strategy).vault());

        // Step 1: Calculate native yield
        uint256 assets = vault.expectedLiquidity();
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        uint256 nativeYield = (vault.baseInterestRate() * vault.totalBorrowed() + vault.quotaRevenue() * RAY)
            * (PERCENTAGE_FACTOR - vault.withdrawFee()) / PERCENTAGE_FACTOR / assets / 1e9;

        uint256 rewardYield = getRewardApr(_strategy, address(vault), _delta);

        // Return total APR (native yield + reward yield)
        return nativeYield + rewardYield;
    }

    function getRewardApr(address _strategy, address _vault, int256 _delta) public view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        IStaking staking = IStaking(strategy.staking());

        // Get farm information from staking contract
        (uint40 farmFinishTime, uint32 farmDuration, uint184 farmReward,) = staking.farmInfo();

        if (farmFinishTime <= block.timestamp) {
            // Farm is finished, no reward yield
            return 0;
        }

        if (farmDuration == 0) {
            // Farm duration is zero, no reward yield
            return 0;
        }

        uint256 gearPerSecond = farmReward / farmDuration;
        
        // Get GEAR price in the ETH from Curve pool
        uint256 ethPerSecond = ICurvePool(GEAR_ETH_CURVE_POOL).get_dy(0, 1, gearPerSecond);

        uint256 assetPerSecond;
        if (strategy.asset() == WETH) {
            assetPerSecond = ethPerSecond;
        } else { 
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = strategy.asset();
            assetPerSecond = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D).getAmountsOut(ethPerSecond, path)[1];   
        }

        // Calculate total supply including the delta converted to shares
        uint256 supply;
        if (_delta < 0) {
            supply = staking.totalSupply() - IVault(_vault).convertToShares(uint256(-_delta));
        } else {
            supply = staking.totalSupply() + IVault(_vault).convertToShares(uint256(_delta));
        }

        // Calculate reward yield
        return assetPerSecond * SECONDS_PER_YEAR * 1e18 / supply;
    }
}