// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AcrossLender} from "./AcrossLender.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract AcrossLenderFactory {
    /// @notice Revert message for when a strategy has already been deployed.
    error AlreadyDeployed(address _strategy);

    event NewAcrossLender(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice Track the deployments. asset => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        require(_management != address(0), "ZERO ADDRESS");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    /**
     * @notice Deploy a new Across Lender.
     * @dev This will set the msg.sender to all of the permissioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newAcrossLender(
        address _asset,
        uint24 _feeBaseToAsset,
        string memory _name
    ) external returns (address) {
        require(msg.sender == management, "!management");
        if (deployments[_asset] != address(0)) revert AlreadyDeployed(deployments[_asset]);
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(
            address(
                new AcrossLender(
                    _asset,
                    _feeBaseToAsset,
                    _name
                )
            )
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setEmergencyAdmin(emergencyAdmin);

        newStrategy.setPendingManagement(management);

        emit NewAcrossLender(address(newStrategy), _asset);

        deployments[_asset] = address(newStrategy);
        return address(newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) external {
        require(msg.sender == management, "!management");
        require(_management != address(0), "address(0)");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
