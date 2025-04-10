// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

contract MockFactory {
    uint16 public feeBps;
    address public recipient;

    constructor(uint16 bps, address treasury) {
        feeBps = bps;
        recipient = treasury;
    }

    function protocolFeeConfig() external view returns (uint16, address) {
        return (feeBps, recipient);
    }

    function updateProtocolFeeConfig(uint16 bps, address treasury) external {
        feeBps = bps;
        recipient = treasury;
    }
}
