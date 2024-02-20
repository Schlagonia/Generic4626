// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// We use the Tokenized Strategy interface.
import {Base4626, ERC20} from "../../Base4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SturdyLender is Base4626 {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        string memory _name,
        address _vault
    ) Base4626(_asset, _name, _vault) {}
}
