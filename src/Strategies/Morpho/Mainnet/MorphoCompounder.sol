// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {Base4626Compounder, ERC20, SafeERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";

interface IAuction {
    function want() external view returns (address);
    function receiver() external view returns (address);
    function kick(address _token) external returns (uint256);
}

contract MorphoCompounder is Base4626Compounder, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    enum SwapType {
        NULL,
        UNISWAP_V3,
        AUCTION
    }

    address public auction;

    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    mapping(address => uint256) public minAmountToSellMapping;

    mapping(address => SwapType) public swapType;

    address[] public allRewardTokens;

    constructor(
        address _asset,
        string memory _name,
        address _vault
    ) Base4626Compounder(_asset, _name, _vault) {}

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
        uint256 _length = _allRewardTokens.length;

        for (uint256 i = 0; i < _length; i++) {
            if (_allRewardTokens[i] == _token) {
                allRewardTokens[i] = _allRewardTokens[_length - 1];
                allRewardTokens.pop();
            }
        }
        delete swapType[_token];
        delete minAmountToSellMapping[_token];
    }

    function getAllRewardTokens() external view returns (address[] memory) {
        return allRewardTokens;
    }

    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(IAuction(_auction).want() == address(asset), "wrong want");
            require(
                IAuction(_auction).receiver() == address(this),
                "wrong receiver"
            );
        }
        auction = _auction;
    }

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
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

    function _claimAndSellRewards() internal override {
        address[] memory _allRewardTokens = allRewardTokens;
        uint256 _length = _allRewardTokens.length;

        for (uint256 i = 0; i < _length; i++) {
            address token = _allRewardTokens[i];
            SwapType _swapType = swapType[token];
            uint256 balance = ERC20(token).balanceOf(address(this));

            if (balance > minAmountToSellMapping[token]) {
                if (_swapType == SwapType.UNISWAP_V3) {
                    _swapFrom(token, address(asset), balance, 0);
                }
            }
        }
    }

    function kickAuction(
        address _token
    ) external onlyKeepers returns (uint256) {
        require(swapType[_token] == SwapType.AUCTION, "!auction");
        return _kickAuction(_token);
    }

    /**
     * @dev Kick an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _kickAuction(address _from) internal virtual returns (uint256) {
        require(
            _from != address(asset) && _from != address(vault),
            "cannot kick"
        );
        uint256 _balance = ERC20(_from).balanceOf(address(this));
        ERC20(_from).safeTransfer(auction, _balance);
        return IAuction(auction).kick(_from);
    }
}
