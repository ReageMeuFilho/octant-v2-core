// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

/**
 * @title DeployYieldDonatingStrategy
 * @author octant.finance
 * @notice Deployment script for YieldDonatingTokenizedStrategy
 * @dev This deploys the YieldDonatingTokenizedStrategy implementation deterministically
 *      using create2 with a salt for consistent addresses across deployments
 */
contract DeployYieldDonatingStrategy is Script {
    // Salt for deterministic deployment - should remain constant between deployments
    bytes32 public constant DEPLOYMENT_SALT = keccak256("OCTANT_YIELD_DONATING_STRATEGY_V1");

    function run() external returns (address) {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Begin deployment with the private key context
        vm.startBroadcast(deployerPrivateKey);
        // print the address of the deployer
        console.log("Deployer public key:", vm.addr(deployerPrivateKey));
        // Get creation bytecode for our contract
        bytes memory creationCode = type(YieldDonatingTokenizedStrategy).creationCode;

        address expectedAddress = _computeCreate2Address(CREATE2_FACTORY, DEPLOYMENT_SALT, keccak256(creationCode));

        console.log("Expected address using CREATE2 factory:", expectedAddress);

        // Deploy the YieldDonatingTokenizedStrategy implementation deterministically using create2
        YieldDonatingTokenizedStrategy strategy = new YieldDonatingTokenizedStrategy{ salt: DEPLOYMENT_SALT }();
        address implementation = address(strategy);

        // Get the asset address to verify constructor behavior
        address asset = strategy.asset();

        // Log deployment information
        console.log("YieldDonatingTokenizedStrategy implementation deployed at:", implementation);

        // Verify constructor behavior - asset should be set to address(1)
        require(asset == address(1), "Constructor did not set asset to address(1)");

        // Log if addresses match or not
        if (expectedAddress == implementation) {
            console.log("Deployment is deterministic as expected!");
        } else {
            revert("Actual address differs from expected address");
        }

        vm.stopBroadcast();

        return implementation;
    }

    /**
     * @notice Helper function to compute the expected address from create2 deployment
     * @param _factory CREATE2 factory address
     * @param _salt Salt used for deployment
     * @param _initCodeHash Hash of the contract's creation code
     * @return Expected deployment address
     */
    function _computeCreate2Address(
        address _factory,
        bytes32 _salt,
        bytes32 _initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", _factory, _salt, _initCodeHash)))));
    }
}
