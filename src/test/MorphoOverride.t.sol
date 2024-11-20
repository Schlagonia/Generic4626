// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";

import {IMorphoCompounder} from "../Strategies/Morpho/interfaces/IMorphoCompounder.sol";
import {MorphoCompounderFactory} from "../Strategies/Morpho/Mainnet/MorphoCompounderFactory.sol";

import {AuctionFactory, Auction} from "@periphery/Auctions/AuctionFactory.sol";

contract MorphoOperationTest is OperationTest {
    MorphoCompounderFactory public morphoCompounderFactory;

    address public MORPHO = 0x9D03bb2092270648d7480049d0E58d2FcF0E5123;

    address public swapToken;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    function setUp() public virtual override {
        super.setUp();

        swapToken = tokenAddrs["USDT"];

        morphoCompounderFactory = new MorphoCompounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            SMS
        );

        // Usual Boosted USDC vault
        vault = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());

        maxFuzzAmount = 1_000_000e6;
        minFuzzAmount = 1e6;
    }

    function setUpMorpho() public virtual returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            morphoCompounderFactory.newMorphoCompounder(vault)
        );

        vm.startPrank(management);
        _strategy.acceptManagement();

        IMorphoCompounder(address(_strategy)).addRewardToken(
            swapToken,
            IMorphoCompounder.SwapType.UNISWAP_V3
        );

        IMorphoCompounder(address(_strategy)).setUniFees(
            swapToken,
            IMorphoCompounder(address(_strategy)).base(),
            100
        );

        IMorphoCompounder(address(_strategy)).setUniFees(
            IMorphoCompounder(address(_strategy)).base(),
            address(asset),
            100
        );

        vm.stopPrank();
        return address(_strategy);
    }
}

contract MorphoWETHOperationTest is MorphoOperationTest {
    function setUp() public virtual override {
        super.setUp();

        // WETH vault
        vault = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());
    }
}

contract MorphoShutdownTest is ShutdownTest {
    MorphoCompounderFactory public morphoCompounderFactory;

    address public MORPHO = 0x9D03bb2092270648d7480049d0E58d2FcF0E5123;

    address public swapToken;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    function setUp() public virtual override {
        super.setUp();

        swapToken = tokenAddrs["USDT"];

        morphoCompounderFactory = new MorphoCompounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            SMS
        );

        // Usual Boosted USDC vault
        vault = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }

    function setUpMorpho() public virtual returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            morphoCompounderFactory.newMorphoCompounder(vault)
        );

        vm.startPrank(management);
        _strategy.acceptManagement();

        IMorphoCompounder(address(_strategy)).addRewardToken(
            swapToken,
            IMorphoCompounder.SwapType.UNISWAP_V3
        );

        IMorphoCompounder(address(_strategy)).setUniFees(
            swapToken,
            IMorphoCompounder(address(_strategy)).base(),
            100
        );

        IMorphoCompounder(address(_strategy)).setUniFees(
            IMorphoCompounder(address(_strategy)).base(),
            address(asset),
            100
        );

        vm.stopPrank();

        return address(_strategy);
    }
}
