// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

contract MockEarningPowerCalculator is IEarningPowerCalculator {
    function getEarningPower(uint256 balance, address, address) external pure returns (uint256) {
        return balance;
    }

    function getNewEarningPower(
        uint256 _amountStaked,
        address,
        address,
        uint256
    ) external pure returns (uint256 _newEarningPower, bool _isQualifiedForBump) {
        return (_amountStaked, false);
    }
}
