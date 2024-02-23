// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";
import {SturdyLenderFactory, SturdyLender} from "../Strategies/Sturdy/SturdyLenderFactory.sol";

contract SturdyOperationTest is OperationTest {
    SturdyLenderFactory public sturdyLenderFactory =
        new SturdyLenderFactory(management, performanceFeeRecipient, keeper);

    function setUp() public virtual override {
        super.setUp();

        // crvusd vault
        vault = 0x73E4C11B670Ef9C025A030A20b72CB9150E54523;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpSturdy());
    }

    function setUpSturdy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            sturdyLenderFactory.newSturdyLender(
                address(asset),
                "Test Sturdy",
                vault
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }
}
contract SturdyShutdownTest is ShutdownTest {
    SturdyLenderFactory public sturdyLenderFactory =
        new SturdyLenderFactory(management, performanceFeeRecipient, keeper);

    function setUp() public virtual override {
        super.setUp();

        // crvusd vault
        vault = 0x73E4C11B670Ef9C025A030A20b72CB9150E54523;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpSturdy());
    }

    function setUpSturdy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            sturdyLenderFactory.newSturdyLender(
                address(asset),
                "Test Sturdy",
                vault
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }
}
