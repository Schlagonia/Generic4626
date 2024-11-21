// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";

import {IAeroRouter} from "../interfaces/Aero/IAeroRouter.sol";

import {IMorphoL2Compounder} from "../Strategies/Morpho/interfaces/IMorphoL2Compounder.sol";
import {MorphoL2CompounderFactory} from "../Strategies/Morpho/L2/MorphoL2CompounderFactory.sol";

contract MorphoL2OperationTest is OperationTest {
    MorphoL2CompounderFactory public morphoL2CompounderFactory;

    address internal constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    address public swapToken;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    address public router = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public base = 0x4200000000000000000000000000000000000006;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        swapToken = 0xA88594D404727625A9437C3f886C7643872296AE;

        morphoL2CompounderFactory = new MorphoL2CompounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            SMS,
            router,
            base
        );

        vault = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());

        maxFuzzAmount = 1_000_000e6;
        minFuzzAmount = 1e6;

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpMorpho() public virtual returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            morphoL2CompounderFactory.newMorphoCompounder(vault)
        );

        vm.startPrank(management);
        _strategy.acceptManagement();
        vm.stopPrank();

        return address(_strategy);
    }

    function test_aerodrome_swap() public {
        uint256 amount = 1000e18;
        uint256 amountToDeposit = 1000e6;
        mintAndDepositIntoStrategy(strategy, user, amountToDeposit);

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).setDoHealthCheck(false);

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).addRewardToken(
            swapToken,
            IMorphoL2Compounder.SwapType.AERODROME
        );

        IAeroRouter.Route[] memory route = new IAeroRouter.Route[](2);

        route[0] = IAeroRouter.Route({
            from: swapToken,
            to: address(base),
            stable: false,
            factory: AERODROME_FACTORY
        });

        route[1] = IAeroRouter.Route({
            from: base,
            to: address(asset),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).setRoutes(
            swapToken,
            address(asset),
            route
        );

        airdrop(ERC20(swapToken), address(strategy), amount);

        assertEq(
            ERC20(swapToken).balanceOf(address(strategy)),
            amount,
            "!swap"
        );
        assertEq(asset.balanceOf(address(strategy)), 0, "!asset");

        vm.prank(keeper);
        strategy.report();

        assertEq(ERC20(swapToken).balanceOf(address(strategy)), 0, "!swap");
        assertEq(asset.balanceOf(address(strategy)), 0, "!asset");
        assertGt(strategy.totalAssets(), amountToDeposit, "!totalAssets");
    }

    function test_uniswapV3_swap() public {
        swapToken = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
        uint256 amount = 1000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).setDoHealthCheck(false);

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).addRewardToken(
            swapToken,
            IMorphoL2Compounder.SwapType.UNISWAP_V3
        );

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).setUniFees(
            swapToken,
            address(asset),
            100
        );

        airdrop(ERC20(swapToken), address(strategy), amount);

        assertEq(
            ERC20(swapToken).balanceOf(address(strategy)),
            amount,
            "!swap"
        );
        assertEq(asset.balanceOf(address(strategy)), 0, "!asset");

        vm.prank(keeper);
        strategy.report();

        assertEq(ERC20(swapToken).balanceOf(address(strategy)), 0, "!swap");
        assertGt(asset.balanceOf(address(strategy)), 0, "!asset");
    }

    function test_allRewardTokens() public {
        vm.expectRevert();
        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).addRewardToken(
            address(asset),
            IMorphoL2Compounder.SwapType.UNISWAP_V3
        );

        vm.expectRevert();
        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).addRewardToken(
            address(vault),
            IMorphoL2Compounder.SwapType.UNISWAP_V3
        );

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).addRewardToken(
            swapToken,
            IMorphoL2Compounder.SwapType.AERODROME
        );

        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens().length,
            1,
            "!length"
        );
        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens()[0],
            swapToken,
            "!swapToken"
        );

        address toAdd = tokenAddrs["DAI"];

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).addRewardToken(
            toAdd,
            IMorphoL2Compounder.SwapType.UNISWAP_V3
        );

        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens().length,
            2,
            "!length"
        );
        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens()[1],
            toAdd,
            "!toAdd"
        );

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).removeRewardToken(swapToken);

        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens().length,
            1,
            "!length"
        );
        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens()[0],
            toAdd,
            "!toAdd"
        );
        assertEq(
            uint256(IMorphoL2Compounder(address(strategy)).swapType(swapToken)),
            0,
            "!swapType"
        );

        vm.prank(management);
        IMorphoL2Compounder(address(strategy)).removeRewardToken(toAdd);

        assertEq(
            IMorphoL2Compounder(address(strategy)).getAllRewardTokens().length,
            0,
            "!length"
        );
        assertEq(
            uint256(IMorphoL2Compounder(address(strategy)).swapType(toAdd)),
            0,
            "!swapType"
        );
    }
}

contract MorphoL2WETHOperationTest is MorphoL2OperationTest {
    function setUp() public virtual override {
        super.setUp();

        // WETH vault
        vault = 0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());
    }
}

contract MorphoL2ShutdownTest is ShutdownTest {
    MorphoL2CompounderFactory public morphoL2CompounderFactory;

    address public swapToken;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    address public router = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public base = 0x4200000000000000000000000000000000000006;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        swapToken = 0xA88594D404727625A9437C3f886C7643872296AE;

        morphoL2CompounderFactory = new MorphoL2CompounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            SMS,
            router,
            base
        );

        vault = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpMorpho() public virtual returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            morphoL2CompounderFactory.newMorphoCompounder(vault)
        );

        vm.startPrank(management);
        _strategy.acceptManagement();
        vm.stopPrank();

        return address(_strategy);
    }
}
