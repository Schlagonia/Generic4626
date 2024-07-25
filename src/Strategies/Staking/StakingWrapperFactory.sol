// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {StakingWrapper} from "./StakingWrapper.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

interface IStakingRegistry {
    function stakingPool(address) external view returns (address);
}

contract StakingWrapperFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    event NewStakingWrapper(address indexed strategy, address indexed asset);

    address public constant SMS = 0x01fE3347316b2223961B20689C65eaeA71348e93;

    address public constant registry =
        0x26d8EA1d8759d0F9abBcf8181b1fD5D3635daD69;

    address public constant keeper = 0x52605BbF54845f520a3E94792d019f62407db2f8;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    /**
     * @notice Deploy a new staking Wrapper for Yearn V3 vault.
     * @param _vault The 4626 vault to deposit into and stake.
     */
    function newStakingWrapper(address _vault) external returns (address) {
        if (deployments[_vault] != address(0))
            revert AlreadyDeployed(deployments[_vault]);

        address _staker = IStakingRegistry(registry).stakingPool(_vault);

        require(_staker != address(0), "No staking contract");

        address _asset = IStrategyInterface(_vault).asset();

        string memory _name = string(
            abi.encode(IStrategyInterface(_vault).name(), " Staking Wrapper")
        );

        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new StakingWrapper(_asset, _name, _vault, _staker))
        );

        newStrategy.setPerformanceFeeRecipient(SMS);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(SMS);

        newStrategy.setPerformanceFee(0);

        emit NewStakingWrapper(address(newStrategy), _asset);

        deployments[_vault] = address(newStrategy);
        return address(newStrategy);
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _vault = address(StakingWrapper(_strategy).vault());
        return deployments[_vault] == _strategy;
    }
}
