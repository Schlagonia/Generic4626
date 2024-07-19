// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";
import {AprOracle, IVault} from "@periphery/AprOracle/AprOracle.sol";
import {ERC20, IStrategy} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {Simulate, IUniswapV3Pool} from "@uniswap-v3-core/libraries/Simulate.sol";

import {SturdyLender} from "../Strategies/Sturdy/SturdyLender.sol";

interface ISturdyRewardConfig {
    struct RewardInfo {
        address rewardToken;
        uint256 epochStart; // block start
        uint256 epochEnd;   // block end
        uint256 amount;
        uint256 decimal;
    }

    struct AggregatorData {
        address aggregator;
        RewardInfo[] rewardInfo;
    }

    function getAllRewardInfo() external view returns (AggregatorData[] memory);
}

interface ICurvePool {
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256 dy);
}

contract CrvUsdSturdyLenderAprOracle is AprOracleBase {
    AprOracle internal constant APR_ORACLE =
        AprOracle(0x27aD2fFc74F74Ed27e1C0A19F1858dD0963277aE);

    ISturdyRewardConfig internal constant STURDY_REWARD_CONFIG =
        ISturdyRewardConfig(0x169A808D414d18F0E5482213b7c77F5B348Fc05a);

    address internal constant STURDY_TOKEN =
        0xaeB3607eC434454ceB308f5Cd540875efb54309A;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNIV3_STURDY_WETH_POOL =
        0xA499B5E6Af1d554316bcd96947940de0c3b5836E;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    ICurvePool internal constant CURVE_TRICRYPTO_CRVUSD_WETH_CRV =
        ICurvePool(0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14);

    uint256 internal constant WAD = 1e18;
    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant SECONDS_PER_BLOCK = 12;

    constructor() AprOracleBase("Sturdy Lender Apr Oracle", msg.sender) {}

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return _apr The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256 _apr) {
        SturdyLender _lenderStrategy = SturdyLender(_strategy);
        IStrategy _sturdyAggregator = _lenderStrategy.vault();

        _apr = APR_ORACLE.getCurrentApr(address(_sturdyAggregator));

        uint256 _vaultShares = _sturdyAggregator.balanceOf(_strategy);
        uint256 _vaultTotalSupply = _sturdyAggregator.totalSupply();
        if (_delta != 0) {
            uint256 _deltaVaultShares = _sturdyAggregator.convertToShares(
                uint256(_delta > 0 ? _delta : -_delta)
            );
            if (_delta > 0) {
                _vaultShares += _deltaVaultShares;
                _vaultTotalSupply += _deltaVaultShares;
            } else {
                _vaultShares -= _deltaVaultShares;
                _vaultTotalSupply -= _deltaVaultShares;
            }
        }

        uint256 _vaultPercentSupply = (_vaultShares * WAD) / _vaultTotalSupply;

        ISturdyRewardConfig.RewardInfo[] memory _rewardInfo = getRewardInfo(
            address(_sturdyAggregator)
        );

        for (uint256 i; i < _rewardInfo.length; ++i) {
            if (_rewardInfo[i].rewardToken != STURDY_TOKEN) continue;
            uint256 _rewardPeriod = (_rewardInfo[i].epochEnd -
                _rewardInfo[i].epochStart) * SECONDS_PER_BLOCK;

            uint256 _rewardAmount = (_rewardInfo[i].amount *
                _vaultPercentSupply) / WAD;

            (, int256 _rewardAmountWeth) = Simulate.simulateSwap(
                IUniswapV3Pool(UNIV3_STURDY_WETH_POOL),
                true,  // zeroForOne, Sturdy < WETH
                int256(_rewardAmount),
                MIN_SQRT_RATIO + 1
            );

            uint256 _rewardAmountCrvUsd = CURVE_TRICRYPTO_CRVUSD_WETH_CRV
                .get_dy(1, 0, uint256(-_rewardAmountWeth));

            _apr +=
                (_rewardAmountCrvUsd * WAD * (ONE_YEAR / _rewardPeriod)) /
                uint256(
                    int256(IVault(address(_lenderStrategy)).totalAssets()) +
                        _delta
                );
        }
    }

    function getRewardInfo(
        address _aggregator
    )
        internal
        view
        returns (ISturdyRewardConfig.RewardInfo[] memory _rewardInfo)
    {
        ISturdyRewardConfig.AggregatorData[]
            memory _rewardInfos = STURDY_REWARD_CONFIG.getAllRewardInfo();

        for (uint256 i; i < _rewardInfos.length; ++i) {
            if (_rewardInfos[i].aggregator == _aggregator)
                return _rewardInfos[i].rewardInfo;
        }
    }
}
