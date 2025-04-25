// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

interface IModuleProxyFactory {
    /// @notice Emitted when a arbitrary proxy is created
    event ModuleProxyCreation(address indexed deployer, address indexed proxy, address indexed masterCopy);

    /// @notice Emitted when a dragon router is created
    event DragonRouterCreation(address indexed owner, address indexed proxy, address indexed masterCopy);

    /// `target` can not be zero.
    error ZeroAddress();

    /// `address_` is already taken.
    error TakenAddress(address address_);

    /// @notice Initialization failed.
    error FailedInitialization();

    /* 
        @dev
        Deploy a module proxy
        @param masterCopy The master copy address
        @param initializer The initializer data
        @param saltNonce The salt nonce
        @return proxy The proxy address
    */
    function deployModule(
        address masterCopy,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address proxy);

    /* 
        @dev
        Deploy a module proxy from a safe
        @param masterCopy The master copy address
        @param data The data to pass to the initializer
        @param saltNonce The salt nonce
        @return proxy The proxy address
    */
    function deployAndEnableModuleFromSafe(
        address masterCopy,
        bytes memory data,
        uint256 saltNonce
    ) external returns (address proxy);

    /* 
        @dev
        Deploy a dragon router
        @param owner The owner of the dragon router
        @param strategies The strategies of the dragon router
        @param opexVault The opex vault of the dragon router
        @param saltNonce The salt nonce
    */
    function deployDragonRouter(
        address owner,
        address[] memory strategies,
        address opexVault,
        uint256 saltNonce
    ) external returns (address payable);

    /* 
        @dev
        Calculate the address of a module proxy
        @param target The target address
        @param salt The salt
        @return proxy The proxy address
    */
    function calculateProxyAddress(address target, bytes32 salt) external view returns (address);

    /* 
        @dev
        Calculate the address of a module proxy
        @param masterCopy The master copy address
        @param initializer The initializer data
        @param saltNonce The salt nonce
    */
    function getModuleAddress(
        address masterCopy,
        bytes memory initializer,
        uint256 saltNonce
    ) external view returns (address);
}
