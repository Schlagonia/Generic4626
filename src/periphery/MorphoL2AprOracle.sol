// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IIrm} from "../interfaces/Morpho/IIrm.sol";
import {MorphoBalancesLib} from "../interfaces/Morpho/libraries/MorphoBalancesLib.sol";
import {IMorpho, Id, Market, MarketParams} from "../interfaces/Morpho/IMorpho.sol";
import {IMetaMorpho} from "../interfaces/Morpho/IMetaMorpho.sol";
import {Simulate, IUniswapV3Pool} from "@uniswap-v3-core/libraries/Simulate.sol";
import {IMorphoCompounder} from "../Strategies/Morpho/interfaces/IMorphoCompounder.sol";
import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

interface IOracle {
    function latestAnswer() external view returns (int256);
}

contract MorphoL2AprOracle is AprOracleBase {
    using MorphoBalancesLib for IMorpho;

    constructor() AprOracleBase("Morpho Apr Oracle", msg.sender) {}

    IMorpho internal constant MORPHO =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IOracle internal constant WETH_USD_ORACLE =
        IOracle(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);

    IOracle internal constant WELL_USD_ORACLE =
        IOracle(0xBBF812FC0e45F58121983bd07C5079fF74433a61);

    address internal constant UNIV3_MORPHO_WETH_POOL =
        0x2F42Df4aF5312B492E9d7F7b2110D9c7bf2D9e4F;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant SECONDS_PER_YEAR = 31_556_952;

    uint256 public morphoRate = 26.45e18;

    uint256 public wellRate = 1_500e18;

    uint256 internal constant PER = 1_000e8;

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view virtual override returns (uint256) {
        uint256 underlyingYield = getUnderlyingYield(
            IMorphoCompounder(_strategy).vault(),
            _delta
        );

        // Give a buffer for the rewards rate
        uint256 rewardsRate = (getRewardsRate() * 9_500) / MAX_BPS;

        return rewardsRate + underlyingYield;
    }

    function getRewardsRate() public view virtual returns (uint256) {
        (int256 _rewardAmountWeth, ) = Simulate.simulateSwap(
            IUniswapV3Pool(UNIV3_MORPHO_WETH_POOL),
            false, // zeroForOne, Morpho > WETH
            int256(morphoRate),
            MAX_SQRT_RATIO - 1
        );

        return
            ((uint256(WETH_USD_ORACLE.latestAnswer()) *
                uint256(-_rewardAmountWeth)) +
                (uint256(WELL_USD_ORACLE.latestAnswer()) * wellRate)) / PER;
    }

    function getUnderlyingYield(
        address _vault,
        int256 _delta
    ) public view virtual returns (uint256) {
        IMetaMorpho metaMorpho = IMetaMorpho(_vault);
        uint256 queueLength = metaMorpho.withdrawQueueLength();
        uint256 totalAssets = metaMorpho.totalAssets();

        uint256 rate = 0;
        for (uint256 i = 0; i < queueLength; i++) {
            Id id = metaMorpho.withdrawQueue(i);
            MarketParams memory marketParams = MORPHO.idToMarketParams(id);

            if (marketParams.irm == address(0)) continue;

            uint256 suppliedAssets = MORPHO.expectedSupplyAssets(
                marketParams,
                _vault
            );

            if (suppliedAssets == 0) continue;

            int256 marketChange = (int256(suppliedAssets) * _delta) /
                int256(totalAssets);

            Market memory market = MORPHO.market(id);

            // Update the supplied assets
            uint128 newSupplyAssets = uint128(
                uint256(
                    int256(uint256(market.totalSupplyAssets)) + marketChange
                )
            );
            market.totalSupplyAssets = newSupplyAssets;

            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(
                marketParams,
                market
            );
            uint256 borrowApy = borrowRate * SECONDS_PER_YEAR;

            uint256 supplyAPY = (borrowApy *
                ((market.totalBorrowAssets * WAD) / newSupplyAssets) *
                (WAD - market.fee)) /
                WAD /
                WAD;

            rate += supplyAPY * newSupplyAssets;
        }

        // Account for the fee
        return
            ((rate / uint256(int256(totalAssets) + _delta)) *
                (WAD - IMetaMorpho(_vault).fee())) / WAD;
    }

    function setMorphoRate(
        uint256 _morphoRate
    ) external virtual onlyGovernance {
        morphoRate = _morphoRate;
    }

    function setWellRate(uint256 _wellRate) external virtual onlyGovernance {
        wellRate = _wellRate;
    }
}
