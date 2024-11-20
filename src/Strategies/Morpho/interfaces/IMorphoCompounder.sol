// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";
import {IStrategyInterface} from "../../../interfaces/IStrategyInterface.sol";

interface IMorphoCompounder is IStrategyInterface, IUniswapV3Swapper {
    enum SwapType {
        UNISWAP_V3,
        AUCTION
    }

    // State Variables
    function auction() external view returns (address);
    function minAmountToSellMapping(address) external view returns (uint256);
    function swapType(address) external view returns (SwapType);
    function allRewardTokens(uint256) external view returns (address);

    // Functions
    function addRewardToken(address _token, SwapType _swapType) external;
    function removeRewardToken(address _token) external;
    function getAllRewardTokens() external view returns (address[] memory);
    function setAuction(address _auction) external;
    function setUniFees(address _token0, address _token1, uint24 _fee) external;
    function setSwapType(address _from, SwapType _swapType) external;
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external;
    function kickAuction(address _token) external;
}
