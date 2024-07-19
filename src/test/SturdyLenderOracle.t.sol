pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";
import {ShutdownTest} from "./Shutdown.t.sol";
import {SturdyLenderFactory, SturdyLender} from "../Strategies/Sturdy/SturdyLenderFactory.sol";


import {CrvUsdSturdyLenderAprOracle} from "../periphery/SturdyLenderAprOracle.sol";

contract CrvUsdSturdyLenderAprOracleTest is Setup {
    SturdyLenderFactory public sturdyLenderFactory =
        new SturdyLenderFactory(management, performanceFeeRecipient, keeper);
    CrvUsdSturdyLenderAprOracle public oracle;

    function setUp() public override {
        super.setUp();
        // crvusd vault
        vault = 0x73E4C11B670Ef9C025A030A20b72CB9150E54523;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpSturdy());

        oracle = new CrvUsdSturdyLenderAprOracle();
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

    function checkOracle(address _strategy, uint256 _delta) public {
        // Check set up
        // TODO: Add checks for the setup

        console.log();
        console.log("Delta: 0");

        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        console.log("Current APR: %e", currentApr);

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");

        console.log();
        console.log("Delta: -%e", _delta);
        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(_strategy, -int256(_delta));

        // The apr should go up if deposits go down
        assertLt(currentApr, negativeDebtChangeApr, "negative change");

        console.log();
        console.log("Delta: %e", _delta);
        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(_strategy, int256(_delta));

        assertGt(currentApr, positiveDebtChangeApr, "positive change");
        assertFalse(true);
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > 10_000e18 && _amount < 10_000_000e18);
        _percentChange = uint16(bound(uint256(_percentChange), 100, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

}
