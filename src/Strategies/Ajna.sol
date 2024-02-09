// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// We use the Tokenized Strategy interface.
import {Base4626, ERC20, IStrategy} from "../Base4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Sturdy is Base4626 {
    using SafeERC20 for ERC20;

    address public immutable compounder;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _compounder
    ) Base4626(_asset, _name, _vault) {
        compounder = _compounder;

        ERC20(_vault).safeApprove(_compounder, type(uint256).max);
    }

    function _stake(uint256 _amount) internal override {
        IStrategy(compounder).deposit(_amount, address(this));
    }

    function _unStake(uint256 _amount) internal override {
        IStrategy(compounder).redeem(
            IStrategy(compounder).convertToShares(_amount),
            address(this),
            address(this)
        );
    }
}
