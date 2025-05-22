// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { MorphoCompounder } from "src/regens/YieldSkimming/strategy/MorphoCompounder.sol";

contract MorphoCompounderWrapper is MorphoCompounder {
    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) MorphoCompounder(_asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress) {}

    // expose _emergencyWithdraw
    function exposeEmergencyWithdraw(uint256 _amount) public {
        _emergencyWithdraw(_amount);
    }

    // expose _freeFunds
    function exposeFreeFunds(uint256 _amount) public {
        _freeFunds(_amount);
    }

    // expose _deployFunds
    function exposeDeployFunds(uint256 _amount) public {
        _deployFunds(_amount);
    }

    // expose _tend
    function exposeTend(uint256 _idle) public {
        _tend(_idle);
    }

    // expose _tendTrigger
    function exposeTendTrigger() public pure returns (bool) {
        return _tendTrigger();
    }
}
