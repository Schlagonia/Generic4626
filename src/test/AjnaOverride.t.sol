// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";
import {AjnaLenderFactory, AjnaLender} from "../Strategies/Ajna/AjnaLenderFactory.sol";

import {AuctionFactory, Auction} from "@periphery/Auctions/AuctionFactory.sol";
import {IAuctionSwapper} from "@periphery/swappers/interfaces/IAuctionSwapper.sol";

contract AjnaOperationTest is OperationTest {
    AjnaLenderFactory public ajnaLenderFactory =
        new AjnaLenderFactory(management, performanceFeeRecipient, keeper);

    address public compounder;
    address public staker;

    function setUp() public virtual override {
        super.setUp();

        // Ajna Weth vault
        vault = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;

        compounder = 0xb974598227660bEfe79a23DFC473D859602254aC;

        staker = 0x0Ed535037c013c3628512980C169Ed59Eb805B49;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }

    function setUpAjna() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            ajnaLenderFactory.newAjnaLender(
                address(asset),
                "Test Ajna",
                vault,
                compounder,
                staker
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

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
    AjnaLenderFactory public ajnaLenderFactory =
        new AjnaLenderFactory(management, performanceFeeRecipient, keeper);

    address public compounder;
    address public staker;

    function setUp() public virtual override {
        super.setUp();

        // Ajna weth vault
        vault = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;

        compounder = 0xb974598227660bEfe79a23DFC473D859602254aC;

        staker = 0x0Ed535037c013c3628512980C169Ed59Eb805B49;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        maxFuzzAmount =
            IStrategyInterface(vault).maxDeposit(address(this)) -
            10;
    }

    function setUpAjna() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            ajnaLenderFactory.newAjnaLender(
                address(asset),
                "Test Ajna",
                vault,
                compounder,
                staker
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

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
