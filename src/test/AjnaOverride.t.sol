// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";

import {IAjnaRouter} from "../interfaces/IStrategyInterface.sol";
import {AjnaRouterFactory, AjnaRouter} from "../Strategies/Ajna/AjnaRouterFactory.sol";

import {AuctionFactory, Auction} from "@periphery/Auctions/AuctionFactory.sol";
import {IAuctionSwapper} from "@periphery/swappers/interfaces/IAuctionSwapper.sol";

contract AjnaOperationTest is OperationTest {
    AjnaRouterFactory public ajnaRouterFactory = new AjnaRouterFactory(keeper);

    address public compounder;
    address public staker;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    function setUp() public virtual override {
        super.setUp();

        // Ajna Weth vault
        vault = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;

        compounder = 0xb974598227660bEfe79a23DFC473D859602254aC;

        staker = 0x0Ed535037c013c3628512980C169Ed59Eb805B49;

        management = SMS;
        performanceFeeRecipient = SMS;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }

    function setUpAjna() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            ajnaRouterFactory.newAjnaRouter(
                address(asset),
                "Test Ajna",
                vault,
                compounder,
                staker
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        vm.prank(SMS);
        IAjnaRouter(address(_strategy)).setDepositor(user);

        return address(_strategy);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public override {
        super.mintAndDepositIntoStrategy(_strategy, _user, _amount);
        vm.prank(IStrategyInterface(compounder).keeper());
        IStrategyInterface(compounder).report();
    }

    // No fees on the Ajna lender
    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public override {
        return;
    }

    function test_whitelist(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        airdrop(asset, management, _amount);

        vm.prank(management);
        asset.approve(address(strategy), _amount);

        vm.expectRevert("ERC4626: deposit more than max");
        vm.prank(management);
        strategy.deposit(_amount, management);

        vm.prank(management);
        IAjnaRouter(address(strategy)).setDepositor(management);

        vm.prank(management);
        strategy.deposit(_amount, management);

        assertEq(strategy.totalAssets(), _amount);
    }
}

contract AjnaDaiOperationTest is AjnaOperationTest {
    function setUp() public virtual override {
        super.setUp();

        // Ajna dai vault
        vault = 0xe24BA27551aBE96Ca401D39761cA2319Ea14e3CB;

        compounder = 0x082a5743aAdf3d0Daf750EeF24652b36a68B1e9C;

        staker = 0x54C6b2b293297e65b1d163C3E8dbc45338bfE443;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }
}

contract AjnaShutdownTest is ShutdownTest {
    AjnaRouterFactory public ajnaRouterFactory = new AjnaRouterFactory(keeper);

    address public compounder;
    address public staker;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    function setUp() public virtual override {
        super.setUp();

        // Ajna weth vault
        vault = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;

        compounder = 0xb974598227660bEfe79a23DFC473D859602254aC;

        staker = 0x0Ed535037c013c3628512980C169Ed59Eb805B49;

        management = SMS;
        performanceFeeRecipient = SMS;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }

    function setUpAjna() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            ajnaRouterFactory.newAjnaRouter(
                address(asset),
                "Test Ajna",
                vault,
                compounder,
                staker
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        vm.prank(SMS);
        IAjnaRouter(address(_strategy)).setDepositor(user);

        return address(_strategy);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public override {
        super.mintAndDepositIntoStrategy(_strategy, _user, _amount);
        vm.prank(IStrategyInterface(compounder).keeper());
        IStrategyInterface(compounder).report();
    }
}

contract AjnaDaiShutdownTest is AjnaShutdownTest {
    function setUp() public virtual override {
        super.setUp();

        // Ajna dai vault
        vault = 0xe24BA27551aBE96Ca401D39761cA2319Ea14e3CB;

        compounder = 0x082a5743aAdf3d0Daf750EeF24652b36a68B1e9C;

        staker = 0x54C6b2b293297e65b1d163C3E8dbc45338bfE443;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }
}
