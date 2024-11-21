// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {SturdyUSDCOracle} from "../src/periphery/SturdyUSDCOracle.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    function run() external {
        vm.startBroadcast();

        SturdyUSDCOracle oracle = new SturdyUSDCOracle();

        console.log("Oracle deployed at", address(oracle));

        vm.stopBroadcast();
    }
}