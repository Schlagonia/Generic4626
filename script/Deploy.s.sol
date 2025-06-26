// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {MorphoAprOracle} from "../src/periphery/MorphoAprOracle.sol";
import {MorphoL2AprOracle} from "../src/periphery/MorphoL2AprOracle.sol";
import {MorphoL2CompounderFactory} from "../src/Strategies/Morpho/L2/MorphoL2CompounderFactory.sol";
import {MorphoCompounderFactory} from "../src/Strategies/Morpho/Mainnet/MorphoCompounderFactory.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

interface IOracle {
    function setOracle(address, address) external;
}

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    address public management = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;

    address public SMS = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;

    address public keeper = 0xC29cbdcf5843f8550530cc5d627e1dd3007EF231;

    function run() external {
        vm.startBroadcast();

        MorphoAprOracle oracle = new MorphoAprOracle();
        console.log("Oracle is ", address(oracle));

        MorphoCompounderFactory factory = new MorphoCompounderFactory(
            deployer,
            SMS,
            keeper,
            SMS
        );

        console.log("Factory is ", address(factory));

        factory.setOracle(address(oracle));

        factory.setAddresses(management, SMS, keeper);
        vm.stopBroadcast();
    }
}