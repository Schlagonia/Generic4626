// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

import {OperationTest} from "./Operation.t.sol";

import {AjnaLenderFactory, AjnaLender} from "../Strategies/Ajna/AjnaLenderFactory.sol";
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

contract AjnaOperationTest is OperationTest {
    AjnaLenderFactory public ajnaLenderFactory =
        new AjnaLenderFactory(management, performanceFeeRecipient, keeper);

    address public staker;
    address public compounder;

    function setUp() public virtual override {
        super.setUp();

        // Ajna Dai compounder and vault.
        staker = 0x54C6b2b293297e65b1d163C3E8dbc45338bfE443;
        compounder = 0x082a5743aAdf3d0Daf750EeF24652b36a68B1e9C;
        vault = 0xe24BA27551aBE96Ca401D39761cA2319Ea14e3CB;

        asset = ERC20(address(IStrategyInterface(vault).asset()));

        strategy = IStrategyInterface(setUpAjna());

        minFuzzAmount = 1e16;
        maxFuzzAmount = IStrategyInterface(vault).maxDeposit(address(this)) - 1;

        vm.label(compounder, "Compounder");
        vm.label(vault, "Ajna Vault");
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
}
