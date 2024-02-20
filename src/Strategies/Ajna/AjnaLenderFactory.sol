// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AjnaLender} from "./AjnaLender.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

contract AjnaLenderFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    event NewAjnaLender(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    /**
     * @notice Deploy a new Ajna Lender.
     * @dev This will set the msg.sender to all of the permissioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newAjnaLender(
        address _asset,
        string memory _name,
        address _vault,
        address _compounder,
        address _staker
    ) external returns (address) {
        if (deployments[_vault] != address(0))
            revert AlreadyDeployed(deployments[_vault]);
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new AjnaLender(_asset, _name, _vault, _compounder, _staker))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        emit NewAjnaLender(address(newStrategy), _asset);

        deployments[_vault] = address(newStrategy);
        return address(newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(address _strategy)
        external
        view
        returns (bool)
    {
        address _vault = address(AjnaLender(_strategy).vault());
        return deployments[_vault] == _strategy;
    }
}
