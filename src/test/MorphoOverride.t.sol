// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";
import {OracleTest, StrategyAprOracle} from "./Oracle.t.sol";

import {MorphoAprOracle} from "../periphery/MorphoAprOracle.sol";
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

    function test_uniswapV3_swap() public {
        uint256 amount = 1000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        vm.prank(management);
        IMorphoCompounder(address(strategy)).setDoHealthCheck(false);

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

    function test_auctionSwap() public {
        uint256 amount = 1000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        airdrop(ERC20(swapToken), address(strategy), amount);

        address auction = AuctionFactory(
            0xa076c247AfA44f8F006CA7f21A4EF59f7e4dc605
        ).createNewAuction(address(asset), address(strategy), management);

        vm.prank(management);
        Auction(auction).enable(swapToken);

        vm.prank(management);
        IMorphoCompounder(address(strategy)).setSwapType(
            swapToken,
            IMorphoCompounder.SwapType.AUCTION
        );

        vm.prank(management);
        IMorphoCompounder(address(strategy)).setAuction(address(auction));

        assertEq(
            ERC20(swapToken).balanceOf(address(strategy)),
            amount,
            "!swap"
        );

        vm.prank(keeper);
        uint256 kicked = IMorphoCompounder(address(strategy)).kickAuction(
            swapToken
        );

        assertEq(kicked, amount, "!kicked");
        assertEq(ERC20(swapToken).balanceOf(address(strategy)), 0, "!swap");
        assertEq(asset.balanceOf(address(strategy)), 0, "!asset");
        assertTrue(Auction(auction).isActive(swapToken), "!active");
    }

    function test_allRewardTokens() public {
        vm.expectRevert();
        vm.prank(management);
        IMorphoCompounder(address(strategy)).addRewardToken(
            address(asset),
            IMorphoCompounder.SwapType.UNISWAP_V3
        );

        vm.expectRevert();
        vm.prank(management);
        IMorphoCompounder(address(strategy)).addRewardToken(
            address(vault),
            IMorphoCompounder.SwapType.UNISWAP_V3
        );

        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens().length,
            1,
            "!length"
        );
        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens()[0],
            swapToken,
            "!swapToken"
        );

        address toAdd = tokenAddrs["DAI"];

        vm.prank(management);
        IMorphoCompounder(address(strategy)).addRewardToken(
            toAdd,
            IMorphoCompounder.SwapType.UNISWAP_V3
        );

        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens().length,
            2,
            "!length"
        );
        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens()[1],
            toAdd,
            "!toAdd"
        );

        vm.prank(management);
        IMorphoCompounder(address(strategy)).removeRewardToken(swapToken);

        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens().length,
            1,
            "!length"
        );
        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens()[0],
            toAdd,
            "!toAdd"
        );
        assertEq(
            uint256(IMorphoCompounder(address(strategy)).swapType(swapToken)),
            0,
            "!swapType"
        );

        vm.prank(management);
        IMorphoCompounder(address(strategy)).removeRewardToken(toAdd);

        assertEq(
            IMorphoCompounder(address(strategy)).getAllRewardTokens().length,
            0,
            "!length"
        );
        assertEq(
            uint256(IMorphoCompounder(address(strategy)).swapType(toAdd)),
            0,
            "!swapType"
        );
    }
}

contract MorphoWETHOperationTest is MorphoOperationTest {
    function setUp() public virtual override {
        super.setUp();

        // WETH vault
        vault = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());

        maxFuzzAmount = 1_000e18;
        minFuzzAmount = 1e16;
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

contract MorphoOracleTest is OracleTest {
    MorphoCompounderFactory public morphoCompounderFactory;

    address public MORPHO = 0x9D03bb2092270648d7480049d0E58d2FcF0E5123;

    address public swapToken;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    function setUp() public virtual override {
        super.setUp();

        swapToken = tokenAddrs["LINK"];

        morphoCompounderFactory = new MorphoCompounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            SMS
        );

        // Usual Boosted USDC vault
        vault = 0x8CB3649114051cA5119141a34C200D65dc0Faa73;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpMorpho());

        maxFuzzAmount = 1_000_000e6;
        minFuzzAmount = 1e6;

        oracle = StrategyAprOracle(address(new MorphoAprOracle()));

        MorphoAprOracle(address(oracle)).setMorphoRate(vault, 6898500000000000);
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

    function test_oracle(uint256 _amount, uint16 _percentChange) public virtual override {
        uint256 rewardsRate = MorphoAprOracle(address(oracle)).getRewardsRate(vault);
        console.log("Rewards rate is ", rewardsRate);
        super.test_oracle(_amount, _percentChange);
    }
}
