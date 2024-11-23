// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {MorphoAprOracle} from "../src/periphery/MorphoAprOracle.sol";
import {MorphoL2CompounderFactory} from "../src/Strategies/Morpho/L2/MorphoL2CompounderFactory.sol";

import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

interface IOracle {
    function setOracle(address, address) external;
}

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public management;

    address public SMS = 0x01fE3347316b2223961B20689C65eaeA71348e93;

    address public keeper = 0x46679Ba8ce6473a9E0867c52b5A50ff97579740E;

    address public router = 0xf6D01e649B5982c50C552f0cFa6eF61A3065Ec48;
    address public base = 0x4200000000000000000000000000000000000006;

    function run() external {
        vm.startBroadcast();

        //MorphoAprOracle oracle = new MorphoAprOracle();

        //console.log("Apr Oracle is ", address(oracle));

        MorphoL2CompounderFactory factory = new MorphoL2CompounderFactory(
            management,
            management,
            keeper,
            SMS,
            router,
            base
        );

        console.log("Factory is ", address(factory));
        
        address vault = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

        address strategy = factory.newMorphoCompounder(vault);

        console.log("Strategy is ", strategy);

        IStrategyInterface(strategy).acceptManagement();

        //factory.setOracle(address(oracle));

        //IOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92).setOracle(strategy, address(oracle));

        vm.stopBroadcast();
    }
}