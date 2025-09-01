// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStaker.sol";

/// @title RegenStaker Factory
/// @notice Deploys RegenStaker contracts with explicit variant selection
/// @author [Golem Foundation](https://golem.foundation)
/// @dev SECURITY: Tracks canonical bytecode per variant from first deployment by factory deployer
/// @dev SECURITY ASSUMPTION: Factory deployer is trusted to provide correct canonical bytecode.
///      If deployer is compromised, all future deployments could use unauthorized code.
///      This is an acceptable risk given the controlled deployment environment.
contract RegenStakerFactory {
    mapping(RegenStakerVariant => bytes32) public canonicalBytecodeHash;

    struct CreateStakerParams {
        IERC20 rewardsToken;
        IERC20 stakeToken;
        address admin;
        IWhitelist stakerWhitelist;
        IWhitelist contributionWhitelist;
        IWhitelist allocationMechanismWhitelist;
        IEarningPowerCalculator earningPowerCalculator;
        uint256 maxBumpTip;
        uint256 maxClaimFee;
        uint256 minimumStakeAmount;
        uint256 rewardDuration;
    }

    enum RegenStakerVariant {
        WITHOUT_DELEGATION,
        WITH_DELEGATION
    }

    // Events
    event StakerDeploy(
        address indexed deployer,
        address indexed admin,
        address indexed stakerAddress,
        bytes32 salt,
        RegenStakerVariant variant
    );

    event CanonicalBytecodeSet(RegenStakerVariant indexed variant, bytes32 indexed bytecodeHash);

    // Errors
    error InvalidBytecode();
    error UnauthorizedBytecode(RegenStakerVariant variant, bytes32 providedHash, bytes32 expectedHash);

    constructor(bytes memory regenStakerBytecode, bytes memory noDelegationBytecode) {
        _canonicalizeBytecode(regenStakerBytecode, RegenStakerVariant.WITH_DELEGATION);
        _canonicalizeBytecode(noDelegationBytecode, RegenStakerVariant.WITHOUT_DELEGATION);
    }

    /// @notice SECURITY: Internal function to canonicalize bytecode without full deployment
    /// @param bytecode The bytecode to canonicalize
    /// @param variant The variant this bytecode represents
    function _canonicalizeBytecode(bytes memory bytecode, RegenStakerVariant variant) private {
        if (bytecode.length == 0) revert InvalidBytecode();

        bytes32 bytecodeHash = keccak256(bytecode);
        canonicalBytecodeHash[variant] = bytecodeHash;

        emit CanonicalBytecodeSet(variant, bytecodeHash);
    }

    /// @notice SECURITY: Modifier to validate bytecode against canonical version
    modifier validatedBytecode(bytes calldata code, RegenStakerVariant variant) {
        _validateBytecode(code, variant);
        _;
    }

    /// @notice Deploy RegenStaker without delegation support
    /// @param params Staker configuration parameters
    /// @param salt Deployment salt for deterministic addressing
    /// @param code Bytecode for WITHOUT_DELEGATION variant
    /// @return stakerAddress Address of deployed contract
    function createStakerWithoutDelegation(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes calldata code
    ) external validatedBytecode(code, RegenStakerVariant.WITHOUT_DELEGATION) returns (address stakerAddress) {
        if (code.length == 0) revert InvalidBytecode();
        stakerAddress = _deployStaker(params, salt, code, RegenStakerVariant.WITHOUT_DELEGATION);
    }

    /// @notice Deploy RegenStaker with delegation support
    /// @param params Staker configuration parameters
    /// @param salt Deployment salt for deterministic addressing
    /// @param code Bytecode for WITH_DELEGATION variant
    /// @return stakerAddress Address of deployed contract
    function createStakerWithDelegation(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes calldata code
    ) external validatedBytecode(code, RegenStakerVariant.WITH_DELEGATION) returns (address stakerAddress) {
        if (code.length == 0) revert InvalidBytecode();
        stakerAddress = _deployStaker(params, salt, code, RegenStakerVariant.WITH_DELEGATION);
    }

    /// @notice Predict deterministic deployment address
    /// @param salt Deployment salt
    /// @param deployer Address that will deploy
    /// @param bytecode The deployment bytecode (including constructor args)
    /// @return Predicted contract address
    function predictStakerAddress(
        bytes32 salt,
        address deployer,
        bytes memory bytecode
    ) external view returns (address) {
        bytes32 finalSalt = keccak256(abi.encode(salt, deployer));
        return Create2.computeAddress(finalSalt, keccak256(bytecode));
    }

    /// @notice SECURITY: Validate bytecode against canonical version
    /// @param code Bytecode to validate
    /// @param variant The RegenStaker variant this bytecode represents
    function _validateBytecode(bytes calldata code, RegenStakerVariant variant) internal view {
        if (code.length == 0) revert InvalidBytecode();

        bytes32 providedHash = keccak256(code);
        bytes32 expectedHash = canonicalBytecodeHash[variant];

        if (providedHash != expectedHash) {
            revert UnauthorizedBytecode(variant, providedHash, expectedHash);
        }
    }

    function _deployStaker(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes memory code,
        RegenStakerVariant variant
    ) internal returns (address stakerAddress) {
        bytes memory constructorParams = _encodeConstructorParams(params);

        bytes memory fullBytecode = bytes.concat(code, constructorParams);
        bytes32 finalSalt = keccak256(abi.encode(salt, msg.sender));

        stakerAddress = Create2.deploy(0, finalSalt, fullBytecode);

        emit StakerDeploy(msg.sender, params.admin, stakerAddress, salt, variant);
    }

    function _encodeConstructorParams(CreateStakerParams calldata params) internal pure returns (bytes memory) {
        return
            abi.encode(
                params.rewardsToken,
                params.stakeToken,
                params.earningPowerCalculator,
                params.maxBumpTip,
                params.admin,
                params.rewardDuration,
                params.maxClaimFee,
                params.minimumStakeAmount,
                params.stakerWhitelist,
                params.contributionWhitelist,
                params.allocationMechanismWhitelist
            );
    }
}
