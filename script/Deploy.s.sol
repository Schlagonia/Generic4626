// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {MorphoAprOracle} from "../src/periphery/MorphoAprOracle.sol";
import {MorphoL2AprOracle} from "../src/periphery/MorphoL2AprOracle.sol";
import {MorphoL2CompounderFactory} from "../src/Strategies/Morpho/L2/MorphoL2CompounderFactory.sol";

import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

interface IOracle {
    function setOracle(address, address) external;
}

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public management = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    address public SMS = 0x16388000546eDed4D476bd2A4A374B5a16125Bc1;

    address public keeper = 0x3A95F75f0Ea2FD60b31E7c6180C7B5fC9865492F;

    address public router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public base = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    function run() external {
        vm.startBroadcast();

        MorphoAprOracle oracle = new MorphoAprOracle();
        console.log("Oracle is ", address(oracle));

        vm.stopBroadcast();
    }
}