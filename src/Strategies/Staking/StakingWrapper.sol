// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

// We use the Tokenized Strategy interface.
import {Base4626Compounder, ERC20, SafeERC20, IStrategy, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";

interface IStaker {
    function balanceOf(address _account) external view returns (uint256);
    function stake(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getReward() external;
    function exit() external;
    function isRetired() external view returns (bool);
}

contract StakingWrapper is Base4626Compounder {
    using SafeERC20 for ERC20;

    address public immutable staker;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _staker
    ) Base4626Compounder(_asset, _name, _vault) {
        staker = _staker;

        ERC20(_vault).safeApprove(staker, type(uint256).max);
    }

    function _stake() internal override {
        IStaker(staker).stake(balanceOfVault());
    }

    function balanceOfStake() public view virtual override returns (uint256) {
        return IStaker(staker).balanceOf(address(this));
    }

    function _unStake(uint256 _amount) internal virtual override {
        IStaker(staker).withdraw(_amount);
    }

    function vaultsMaxWithdraw()
        public
        view
        virtual
        override
        returns (uint256)
    {
        // We need to use the staking contract address for maxRedeem
        // Convert the vault shares to `asset`.
        return vault.convertToAssets(vault.maxRedeem(staker));
    }

    function getReward() external {
        _claimAndSellRewards();
    }

    function _claimAndSellRewards() internal override {
        IStaker(staker).getReward();
        // TODO: Send claimed tokens to somewhere
    }

    function availableDepositLimit(
        address /*_owner*/
    ) public view virtual override returns (uint256) {
        // Return the max amount the vault will allow for deposits.
        return vault.maxDeposit(address(this));
    }
}
