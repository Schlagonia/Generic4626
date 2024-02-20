// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// We use the Tokenized Strategy interface.
import {Base4626, ERC20, IStrategy} from "../../Base4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    function _stake(uint256 _amount) internal override {
        IStrategy(compounder).deposit(_amount, address(this));
    }

    function balanceOfStake() public view virtual override returns (uint256) {
        return
            IStrategy(compounder).convertToAssets(
                IStrategy(compounder).balanceOf(address(this))
            );
    }

    function _unStake(uint256 _amount) internal virtual override {
        IStrategy(compounder).redeem(
            IStrategy(compounder).convertToShares(_amount),
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
        uint256 redeemable;

        // If the vaults shares are held in the strategy use this address for maxRedeem
        if (balanceOfVault() != 0) redeemable += vault.maxRedeem(address(this));

        // Else if the compounder holds the vault shares.
        if (IStrategy(compounder).balanceOf(address(this)) != 0)
            // We need to use the staking contract address for maxRedeem
            redeemable += vault.maxRedeem(staker);

        // Convert the vault shares to `asset`.
        return vault.convertToAssets(redeemable);
    }
}
