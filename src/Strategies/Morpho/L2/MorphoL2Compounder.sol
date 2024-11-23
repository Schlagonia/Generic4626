// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IAeroRouter} from "../../../interfaces/Aero/IAeroRouter.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {Base4626Compounder, ERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";

contract MorphoL2Compounder is
    Base4626Compounder,
    TradeFactorySwapper,
    UniswapV3Swapper
{
    enum SwapType {
        NULL,
        AERODROME,
        UNISWAP_V3,
        TRADE_FACTORY
    }

    IAeroRouter internal constant AERODROME_ROUTER =
        IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    mapping(address => mapping(address => IAeroRouter.Route[])) public routes;

    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    mapping(address => uint256) public minAmountToSellMapping;

    mapping(address => SwapType) public swapType;

    address[] public allRewardTokens;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _router,
        address _base
    ) Base4626Compounder(_asset, _name, _vault) {
        router = _router;
        base = _base;
    }

    function addRewardToken(
        address _token,
        SwapType _swapType
    ) external onlyManagement {
        require(
            _token != address(asset) && _token != address(vault),
            "cannot be a reward token"
        );
        allRewardTokens.push(_token);
        swapType[_token] = _swapType;
    }

    function removeRewardToken(address _token) external onlyManagement {
        address[] memory _allRewardTokens = allRewardTokens;

        for (uint256 i = 0; i < _allRewardTokens.length; i++) {
            if (_allRewardTokens[i] == _token) {
                allRewardTokens[i] = _allRewardTokens[
                    _allRewardTokens.length - 1
                ];
                allRewardTokens.pop();
            }
        }
        delete swapType[_token];
        delete minAmountToSellMapping[_token];
    }

    function getAllRewardTokens() external view returns (address[] memory) {
        return allRewardTokens;
    }

    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    function enableTradeFactoryToken(address _token) external onlyManagement {
        require(
            _token != address(asset) && _token != address(vault),
            "cannot enable"
        );
        _addToken(_token, address(asset));
    }

    function disableTradeFactoryToken(address _token) external onlyManagement {
        _removeToken(_token, address(asset));
    }

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    function setRoutes(
        address _token0,
        address _token1,
        IAeroRouter.Route[] calldata _routes
    ) external onlyManagement {
        delete routes[_token0][_token1];

        for (uint256 i = 0; i < _routes.length; i++) {
            routes[_token0][_token1].push(_routes[i]);
        }
    }

    /**
     * @notice Set the swap type for a specific token.
     * @param _from The address of the token to set the swap type for.
     * @param _swapType The swap type to set.
     */
    function setSwapType(
        address _from,
        SwapType _swapType
    ) external onlyManagement {
        swapType[_from] = _swapType;
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

    function _claimRewards() internal override {}

    function _claimAndSellRewards() internal override {
        address[] memory _allRewardTokens = allRewardTokens;

        for (uint256 i = 0; i < _allRewardTokens.length; i++) {
            address token = _allRewardTokens[i];
            SwapType _swapType = swapType[token];
            uint256 balance = ERC20(token).balanceOf(address(this));

            if (balance > minAmountToSellMapping[token]) {
                if (_swapType == SwapType.UNISWAP_V3) {
                    _swapFrom(token, address(asset), balance, 0);
                } else if (_swapType == SwapType.AERODROME) {
                    _aerodromeSwapFrom(token, address(asset), balance, 0);
                }
            }
        }

        // Redeploy to new yield source.
        uint256 toDeploy = Math.min(
            balanceOfAsset(),
            availableDepositLimit(address(this))
        );

        if (toDeploy > 0) {
            _deployFunds(toDeploy);
        }
    }

    function _aerodromeSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual {
        if (_amountIn > minAmountToSellMapping[_from]) {
            _checkAllowance(address(AERODROME_ROUTER), _from, _amountIn);

            AERODROME_ROUTER.swapExactTokensForTokens(
                _amountIn,
                _minAmountOut,
                routes[_from][_to],
                address(this),
                block.timestamp
            );
        }
    }
}
