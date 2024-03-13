// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";

interface IStrategyInterface is IBase4626Compounder {}

interface IAjnaRouter is IStrategyInterface {
    function depositor() external view returns (address);
    function setDepositor(address _depositor) external;
}
