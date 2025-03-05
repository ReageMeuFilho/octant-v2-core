// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { MantleMehTokenizedStrategy } from "src/dragons/modules/MantleMehTokenizedStrategy.sol";
import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { console } from "forge-std/console.sol";

/**
 * @title MockMantleMehTokenizedStrategy
 * @notice Mock version of MantleMehTokenizedStrategy for testing
 */
contract MockMantleMehTokenizedStrategy is MantleMehTokenizedStrategy {
    // Mock addresses that will be used instead of the hardcoded constants
    address public mockMantleStaking;
    address public mockMethToken;

    // Real addresses (for reference)
    address public constant REAL_MANTLE_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address public constant REAL_METH_TOKEN = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;

    /**
     * @notice Initialize function for the strategy to work with ERC1967Proxy
     */
    function initialize(
        address _asset,
        string memory _name,
        address _operator,
        address _management,
        address _keeper,
        address _dragonRouter,
        address _regenGovernance
    ) external {
        console.log("MockMantleMehTokenizedStrategy.initialize called");
        console.log("  _asset:", _asset);
        console.log("  _name:", _name);
        console.log("  _operator:", _operator);
        console.log("  _management:", _management);
        console.log("  _keeper:", _keeper);
        console.log("  _dragonRouter:", _dragonRouter);

        // Convert to the format needed by setUp
        bytes memory data = abi.encode(
            address(0), // tokenizedStrategyImplementation - will be ignored in test
            _management,
            _keeper,
            _dragonRouter,
            uint256(604800), // default maxReportDelay (7 days)
            _regenGovernance
        );

        // Create the initialize params for the parent contract
        bytes memory initializeParams = abi.encode(_operator, data);

        // Call the parent's setUp function
        setUp(initializeParams);

        // give allowance to the mantlestaking contract
        IERC20(mockMethToken).approve(mockMantleStaking, type(uint256).max);

        console.log("MockMantleMehTokenizedStrategy initialization complete");
    }

    /**
     * @notice Set mock addresses for testing
     * @param _mockMantleStaking Mock address for Mantle staking
     * @param _mockMethToken Mock address for mETH token
     */
    function setMockAddresses(address _mockMantleStaking, address _mockMethToken) external {
        mockMantleStaking = _mockMantleStaking;
        mockMethToken = _mockMethToken;

        // Approve the mock staking contract to spend our mock mETH tokens
        IERC20(_mockMethToken).approve(_mockMantleStaking, type(uint256).max);
    }
}
