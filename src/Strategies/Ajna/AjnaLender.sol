// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// We use the Tokenized Strategy interface.
import {Base4626, ERC20, SafeERC20, IStrategy, Math} from "../../Base4626.sol";

contract AjnaLender is Base4626 {
    using SafeERC20 for ERC20;

    address public immutable compounder;

    address public immutable staker;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _compounder,
        address _staker
    ) Base4626(_asset, _name, _vault) {
        compounder = _compounder;
        staker = _staker;

        ERC20(_vault).safeApprove(_compounder, type(uint256).max);
    }

    function _stake() internal override {
        IStrategy(compounder).deposit(balanceOfVault(), address(this));
    }

    function balanceOfStake() public view virtual override returns (uint256) {
        return
            IStrategy(compounder).convertToAssets(
                IStrategy(compounder).balanceOf(address(this))
            );
    }

    function _unStake(uint256 _amount) internal virtual override {
        IStrategy(compounder).redeem(
            Math.min(
                IStrategy(compounder).convertToShares(_amount),
                IStrategy(compounder).balanceOf(address(this))
            ),
            address(this),
            address(this)
        );
    }

    function vaultsMaxWithdraw()
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO: Use the compounders maxWithdraw
        // We need to use the staking contract address for maxRedeem
        // Convert the vault shares to `asset`.
        return vault.convertToAssets(vault.maxRedeem(staker));
    }
}
