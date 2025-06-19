// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {MorphoL2Compounder} from "./MorphoL2Compounder.sol";
import {IStrategyInterface} from "../../../interfaces/IStrategyInterface.sol";

interface IOracle {
    function setOracle(address, address) external;
}

contract MorphoL2CompounderFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    event NewMorphoCompounder(address indexed strategy, address indexed asset);

    address internal constant APR_ORACLE =
        0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92;

    address public immutable SMS;

    address public immutable BASE;

    address public immutable ROUTER;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public aprOracle;

    /// @notice Track the deployments. vault => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _sms,
        address _router,
        address _base
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        SMS = _sms;
        ROUTER = _router;
        BASE = _base;
    }

    /**
     * @notice Deploy a new Morpho L2 Compounder.
     * @param _vault The vault to deploy the strategy for.
     * @return . The address of the new lender.
     */
    function newMorphoCompounder(address _vault) external returns (address) {
        if (deployments[_vault] != address(0))
            revert AlreadyDeployed(deployments[_vault]);

        address _asset = IStrategyInterface(_vault).asset();
        string memory _name = string(
            abi.encodePacked(
                "Morpho ",
                IStrategyInterface(_vault).name(),
                " Compounder"
            )
        );

        // We need to use the custom interface with the
        // tokenized strategies setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new MorphoL2Compounder(_asset, _name, _vault, ROUTER, BASE))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setEmergencyAdmin(SMS);

        newStrategy.setProfitMaxUnlockTime(60 * 60 * 24 * 2);

        IOracle(APR_ORACLE).setOracle(address(newStrategy), aprOracle);

        newStrategy.setPendingManagement(management);

        emit NewMorphoCompounder(address(newStrategy), _asset);

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

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _vault = address(MorphoL2Compounder(_strategy).vault());
        return deployments[_vault] == _strategy;
    }

    function setOracle(address _oracle) external {
        require(msg.sender == management, "!management");
        aprOracle = _oracle;
    }
}
