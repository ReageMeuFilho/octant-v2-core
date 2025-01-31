// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IBaseStrategy {
    function tokenizedStrategyAddress() external view returns (address);

    function owner() external view returns (address);
    function avatar() external view returns (address);
    function target() external view returns (address);
    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function maxReportDelay() external view returns (uint256);

    function tokenizedStrategyImplementation() external view returns (address);

    function availableDepositLimit(address _owner) external view returns (uint256);

    function availableWithdrawLimit(address _owner) external view returns (uint256);

    function deployFunds(uint256 _assets) external;

    function freeFunds(uint256 _amount) external;

    function harvestTrigger() external view returns (bool);

    function harvestAndReport() external returns (uint256);

    function tendThis(uint256 _totalIdle) external;

    function shutdownWithdraw(uint256 _amount) external;

    function tendTrigger() external view returns (bool, bytes memory);

    function adjustPosition(uint256 _debtOutstanding) external;

    function liquidatePosition(uint256 _amountNeeded) external returns (uint256 _liquidatedAmount, uint256 _loss);
}
