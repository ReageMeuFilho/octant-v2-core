// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { MockYieldSource } from "../MockYieldSource.sol";
import { BaseStrategy, ERC20 } from "src/core/BaseStrategy.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { console2 } from "forge-std/console2.sol";
import { MockYieldSourceSkimming } from "./MockYieldSourceSkimming.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStrategySkimming is BaseStrategy {
    address public yieldSource;
    bool public trigger;
    bool public managed;
    bool public kept;
    bool public emergentizated;
    address public yieldSourceSkimming;

    // Track the last reported total assets to calculate profit
    uint256 private lastReportedPPS;

    constructor(
        address _yieldSource,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) BaseStrategy(_yieldSource, "Test Strategy", _management, _keeper, _emergencyAdmin, _donationAddress) {
        initialize(_yieldSource, _yieldSource);
        yieldSourceSkimming = _yieldSource;
        lastReportedPPS = MockYieldSourceSkimming(_yieldSource).pricePerShare();
    }

    function initialize(address _asset, address _yieldSource) public {
        require(yieldSource == address(0));
        yieldSource = _yieldSource;
        ERC20(_asset).approve(_yieldSource, type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal override {}

    function _freeFunds(uint256 /*_amount*/) internal override {}

    function _harvestAndReport() internal override returns (uint256) {
        uint256 currentPPS = MockYieldSourceSkimming(yieldSourceSkimming).pricePerShare();

        // Get the total assets controlled by the strategy (not just idle balance)
        uint256 totalAssets = ERC20(yieldSourceSkimming).balanceOf(address(this));

        // Calculate the profit based on exchange rate difference
        uint256 deltaExchangeRate = currentPPS > lastReportedPPS ? currentPPS - lastReportedPPS : 0; // Only capture positive yield

        // Calculate profit with better precision handling
        // profit = totalAssets * (deltaExchangeRate / currentPPS)
        uint256 profitInYieldVaultShares = (totalAssets * deltaExchangeRate) / currentPPS;

        lastReportedPPS = currentPPS;

        return profitInYieldVaultShares;
    }

    function _tend(uint256 /*_idle*/) internal override {}

    function _emergencyWithdraw(uint256 /*_amount*/) internal override {}

    function _tendTrigger() internal view override returns (bool) {
        return trigger;
    }

    function setTrigger(bool _trigger) external {
        trigger = _trigger;
    }

    function onlyLetManagers() public onlyManagement {
        managed = true;
    }

    function onlyLetKeepersIn() public onlyKeepers {
        kept = true;
    }

    function onlyLetEmergencyAdminsIn() public onlyEmergencyAuthorized {
        emergentizated = true;
    }
}
