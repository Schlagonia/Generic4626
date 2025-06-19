// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IAeroRouter} from "../../../interfaces/Aero/IAeroRouter.sol";
import {ITradeFactorySwapper} from "@periphery/swappers/interfaces/ITradeFactorySwapper.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";
import {IStrategyInterface} from "../../../interfaces/IStrategyInterface.sol";

interface IMorphoL2Compounder is
    IStrategyInterface,
    IUniswapV3Swapper,
    ITradeFactorySwapper
{
    enum SwapType {
        NULL,
        AERODROME,
        UNISWAP_V3,
        TRADE_FACTORY
    }

    // Public/External State Variables
    function routes(
        address,
        address,
        uint256
    ) external view returns (IAeroRouter.Route memory);
    function minAmountToSellMapping(address) external view returns (uint256);
    function swapType(address) external view returns (SwapType);
    function allRewardTokens(uint256) external view returns (address);

    // External Functions
    function addRewardToken(address _token, SwapType _swapType) external;
    function removeRewardToken(address _token) external;
    function getAllRewardTokens() external view returns (address[] memory);
    function setTradeFactory(address _tradeFactory) external;
    function enableTradeFactoryToken(address _token) external;
    function disableTradeFactoryToken(address _token) external;
    function setUniFees(address _token0, address _token1, uint24 _fee) external;
    function setRoutes(
        address _token0,
        address _token1,
        IAeroRouter.Route[] calldata _routes
    ) external;
    function setSwapType(address _from, SwapType _swapType) external;
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external;
}
