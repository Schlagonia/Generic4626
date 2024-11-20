// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

interface IAjnaRouter is IStrategyInterface {
    function depositor() external view returns (address);
    function setDepositor(address _depositor) external;
}
