// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/Safe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import { LibString } from "solady/utils/LibString.sol";

/**
 * @title DeploySafe
 * @notice Script to deploy a configurable Safe multisig with transaction execution utilities
 * @dev Uses Safe singleton and proxy factory pattern for gas efficient deployments
 */
contract DeploySafe is Test {
    using LibString for *;

    // Default configuration for 5/9 multisig
    uint256 public constant DEFAULT_THRESHOLD = 5;
    uint256 public constant DEFAULT_TOTAL_OWNERS = 9;

    // Configurable parameters
    uint256 public threshold;
    uint256 public totalOwners;

    // Dynamic owner array
    address[] public owners;

    // Safe contract addresses
    address public safeSingleton;
    address public safeProxyFactoryAddress;

    // Deployed Safe instance
    Safe public deployedSafe;

    error InvalidSafeSetup();
    error InvalidOwnerAddress();
    error InvalidThreshold();

    /**
     * @notice Initialize the Safe setup with provided addresses and configuration
     * @param _safeSingleton Safe singleton contract address
     * @param _safeProxyFactory Safe proxy factory address
     * @param _owners Array of owner addresses
     * @param _threshold Number of required signatures
     */
    function setUpSafeDeployParams(
        address _safeSingleton,
        address _safeProxyFactory,
        address[] memory _owners,
        uint256 _threshold
    ) public virtual {
        // Validate inputs
        if (_safeSingleton == address(0) || _safeProxyFactory == address(0)) {
            revert InvalidSafeSetup();
        }
        if (_threshold == 0 || _threshold > _owners.length) {
            revert InvalidThreshold();
        }

        safeSingleton = _safeSingleton;
        safeProxyFactoryAddress = _safeProxyFactory;
        threshold = _threshold;
        totalOwners = _owners.length;

        // Clear and set owners
        delete owners;
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == address(0)) {
                revert InvalidOwnerAddress();
            }
            owners.push(_owners[i]);
        }
    }

    /**
     * @notice Generates the initialization data for the Safe setup
     */
    function generateInitializerData() internal view returns (bytes memory initializer) {
        initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            address(0), // No module
            bytes(""), // Empty setup data
            address(0), // No fallback handler
            address(0), // No payment token
            0, // No payment
            address(0) // No payment receiver
        );
    }

    function deploy() public virtual {
        bool needsSetup = safeSingleton == address(0) || safeProxyFactoryAddress == address(0) || owners.length == 0;
        if (needsSetup) {
            // Try to get threshold from environment, default to 5
            uint256 configuredThreshold;
            try vm.envUint("SAFE_THRESHOLD") returns (uint256 value) {
                configuredThreshold = value;
            } catch {
                configuredThreshold = DEFAULT_THRESHOLD;
            }

            // Try to get total owners from environment, default to 9
            uint256 configuredTotalOwners;
            try vm.envUint("SAFE_TOTAL_OWNERS") returns (uint256 value) {
                configuredTotalOwners = value;
            } catch {
                configuredTotalOwners = DEFAULT_TOTAL_OWNERS;
            }

            // Generate owner addresses from environment
            address[] memory _owners = new address[](configuredTotalOwners);
            for (uint256 i = 0; i < configuredTotalOwners; i++) {
                string memory key = string.concat("SAFE_OWNER", (i + 1).toString());
                _owners[i] = vm.envAddress(key);
            }

            // Set up deployment parameters
            setUpSafeDeployParams(
                vm.envAddress("SAFE_SINGLETON"),
                vm.envAddress("SAFE_PROXY_FACTORY"),
                _owners,
                configuredThreshold
            );
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get initialization data
        bytes memory initializer = generateInitializerData();

        // Deploy new Safe via factory
        SafeProxyFactory factory = SafeProxyFactory(safeProxyFactoryAddress);
        SafeProxy proxy = factory.createProxyWithNonce(
            safeSingleton,
            initializer,
            block.timestamp // Use timestamp as salt
        );

        // Store deployed Safe
        deployedSafe = Safe(payable(address(proxy)));

        vm.stopBroadcast();

        // Log deployment info
        // console.log("Safe deployed at:", address(proxy));
        // console.log("Threshold:", threshold);
        // console.log("\nOwners:");
        // for (uint256 i = 0; i < owners.length; i++) {
        //     console.log(string.concat("Owner ", (i + 1).toString(), ": ", owners[i].toHexString()));
        // }
    }
}
