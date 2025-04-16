// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.0;

import { ISafe } from "../interfaces/Safe.sol";
import { IModuleProxyFactory } from "../interfaces/IModuleProxyFactory.sol";

contract ModuleProxyFactory is IModuleProxyFactory {
    /// @notice The governance address
    address public immutable GOVERNANCE;
    /// @notice The regen governance address
    address public immutable REGEN_GOVERNANCE;
    /// @notice The split checker proxy address
    address public immutable SPLIT_CHECKER;
    /// @notice The metapool address
    address public immutable METAPOOL;
    /// @notice The dragon router implementation address
    address public immutable DRAGON_ROUTER_IMPLEMENTATION;

    /// @notice Constructor
    /// @param _governance The governance address
    /// @param _regenGovernance The regen governance address
    /// @param _splitCheckerImplementation The split checker proxy address
    /// @param _metapool The metapool address
    /// @param _dragonRouterImplementation The dragon router implementation address
    constructor(
        address _governance,
        address _regenGovernance,
        address _metapool,
        address _splitCheckerImplementation,
        address _dragonRouterImplementation
    ) {
        _ensureNonzeroAddress(_governance);
        _ensureNonzeroAddress(_regenGovernance);
        _ensureNonzeroAddress(_splitCheckerImplementation);
        _ensureNonzeroAddress(_metapool);
        _ensureNonzeroAddress(_dragonRouterImplementation);
        GOVERNANCE = _governance;
        REGEN_GOVERNANCE = _regenGovernance;
        uint256 DEFAULT_MAX_OPEX_SPLIT = 0.5e18;
        uint256 DEFAULT_MIN_METAPOOL_SPLIT = 0.05e18;
        SPLIT_CHECKER = deployModule(
            _splitCheckerImplementation,
            abi.encodeWithSignature(
                "initialize(address,uint256,uint256)",
                GOVERNANCE,
                DEFAULT_MAX_OPEX_SPLIT,
                DEFAULT_MIN_METAPOOL_SPLIT
            ),
            block.timestamp
        );
        METAPOOL = _metapool;
        DRAGON_ROUTER_IMPLEMENTATION = _dragonRouterImplementation;
    }

    /// @notice Creates a proxy for an arbitrary target
    /// @param target The target address
    /// @param salt The salt value
    /// @return result The proxy address
    /// @custom:error ZeroAddress is thrown if the provided address is a zero address
    /// @custom:error TargetHasNoCode is thrown if the provided address has no code deployed
    function createProxy(address target, bytes32 salt) internal returns (address payable result) {
        _ensureNonzeroAddress(target);
        // NOTE: Magic number https://github.com/thebor1337/solidity_sandbox/blob/f8a678f4cbabd22831e646830e299c75e75dd76f/contracts/Proxy/ERC1167/Proxy.huff#L4
        bytes memory deployment = abi.encodePacked(
            hex"602d8060093d393df3363d3d373d3d3d363d73",
            target,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        // solhint-disable-next-line no-inline-assembly
        assembly {
            result := create2(0, add(deployment, 0x20), mload(deployment), salt)
        }
        if (result == address(0)) revert TakenAddress(result);
    }

    /// @notice Deploys a module proxy
    /// @param masterCopy The master copy address
    /// @param initializer The initializer data
    /// @param saltNonce The salt nonce
    /// @return proxy The proxy address
    function deployModule(
        address masterCopy,
        bytes memory initializer,
        uint256 saltNonce
    ) public returns (address proxy) {
        proxy = createProxy(masterCopy, keccak256(abi.encodePacked(keccak256(initializer), saltNonce)));
        (bool success, ) = proxy.call(initializer);
        if (!success) revert FailedInitialization();

        emit ModuleProxyCreation(msg.sender, proxy, masterCopy);
    }

    /// @notice Deploys a dragon router
    /// @param owner The owner address (the dragon vault safe)
    /// @param strategies The strategies addresses
    /// @param opexVault The opex vault address
    /// @param saltNonce The salt nonce
    /// @return proxy The proxy address
    function deployDragonRouter(
        address owner,
        address[] memory strategies,
        address opexVault,
        uint256 saltNonce
    ) public returns (address payable) {
        _ensureNonzeroAddress(owner);
        _ensureNonzeroAddress(opexVault);
        bytes memory data = abi.encode(strategies, GOVERNANCE, REGEN_GOVERNANCE, SPLIT_CHECKER, opexVault, METAPOOL);
        bytes memory initializer = abi.encode(owner, data);

        address payable proxy = payable(
            deployModule(DRAGON_ROUTER_IMPLEMENTATION, abi.encodeWithSignature("setUp(bytes)", initializer), saltNonce)
        );

        emit DragonRouterCreation(proxy, DRAGON_ROUTER_IMPLEMENTATION, owner);
        return proxy;
    }

    /// @notice Deploys a module and enables it on the provided safe
    /// @param masterCopy The master copy address
    /// @param data The data to pass to the initializer
    /// @param saltNonce The salt nonce
    /// @return proxy The proxy address
    function deployAndEnableModuleFromSafe(
        address masterCopy,
        bytes memory data,
        uint256 saltNonce
    ) public returns (address proxy) {
        proxy = deployModule(
            masterCopy,
            abi.encodeWithSignature("setUp(bytes)", abi.encode(address(this), data)),
            saltNonce
        );

        ISafe(address(this)).enableModule(proxy);
    }

    /// @notice Checks if the provided address is nonzero, reverts otherwise
    /// @param address_ Address to check
    /// @custom:error ZeroAddress is thrown if the provided address is a zero address
    function _ensureNonzeroAddress(address address_) internal pure {
        if (address_ == address(0)) {
            revert ZeroAddress();
        }
    }
}
