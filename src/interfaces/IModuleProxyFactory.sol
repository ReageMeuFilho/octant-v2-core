// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

interface IModuleProxyFactory {
    /// @notice Emitted when a arbitrary proxy is created
    event ModuleProxyCreation(address indexed deployer, address indexed proxy, address indexed masterCopy);

    /// @notice Emitted when a dragon router is created
    event DragonRouterCreation(address indexed proxy, address indexed masterCopy, address indexed owner);

    /// `target` can not be zero.
    error ZeroAddress();

    /// `address_` is already taken.
    error TakenAddress(address address_);

    /// @notice Initialization failed.
    error FailedInitialization();

    function deployModule(
        address masterCopy,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address proxy);

    function deployAndEnableModuleFromSafe(
        address masterCopy,
        bytes memory data,
        uint256 saltNonce
    ) external returns (address proxy);

    function deployDragonRouter(
        address owner,
        address[] memory strategies,
        address opexVault,
        uint256 saltNonce
    ) external returns (address payable);
}
