// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CREATE3 } from "solady/utils/CREATE3.sol";
import { IERC20, IERC20Staking, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStaker.sol";

/// @title RegenStaker Factory
/// @notice Deploys RegenStaker contracts with explicit variant selection
/// @author [Golem Foundation](https://golem.foundation)
/// @dev SECURITY: Tracks canonical bytecode per variant from first deployment by factory deployer
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
        NO_DELEGATION,
        ERC20_STAKING
    }

    event StakerDeploy(
        address indexed deployer,
        address indexed admin,
        address indexed stakerAddress,
        bytes32 salt,
        RegenStakerVariant variant
    );

    event CanonicalBytecodeSet(RegenStakerVariant indexed variant, bytes32 indexed bytecodeHash);

    error InvalidBytecode();
    error UnauthorizedBytecode(RegenStakerVariant variant, bytes32 providedHash, bytes32 expectedHash);

    constructor(bytes memory regenStakerBytecode, bytes memory noDelegationBytecode) {
        _canonicalizeBytecode(regenStakerBytecode, RegenStakerVariant.ERC20_STAKING);
        _canonicalizeBytecode(noDelegationBytecode, RegenStakerVariant.NO_DELEGATION);
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
    /// @param code Bytecode for NO_DELEGATION variant
    /// @return stakerAddress Address of deployed contract
    function createStakerNoDelegation(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes calldata code
    ) external validatedBytecode(code, RegenStakerVariant.NO_DELEGATION) returns (address stakerAddress) {
        if (code.length == 0) revert InvalidBytecode();
        stakerAddress = _deployStaker(params, salt, code, RegenStakerVariant.NO_DELEGATION);
    }

    /// @notice Deploy RegenStaker with delegation support
    /// @param params Staker configuration parameters
    /// @param salt Deployment salt for deterministic addressing
    /// @param code Bytecode for ERC20_STAKING variant
    /// @return stakerAddress Address of deployed contract
    function createStakerERC20Staking(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes calldata code
    ) external validatedBytecode(code, RegenStakerVariant.ERC20_STAKING) returns (address stakerAddress) {
        if (code.length == 0) revert InvalidBytecode();
        stakerAddress = _deployStaker(params, salt, code, RegenStakerVariant.ERC20_STAKING);
    }

    /// @notice Predict deterministic deployment address
    /// @param salt Deployment salt
    /// @param deployer Address that will deploy
    /// @return Predicted contract address
    function predictStakerAddress(bytes32 salt, address deployer) external view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(salt, deployer)));
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

        stakerAddress = CREATE3.deployDeterministic(
            bytes.concat(code, constructorParams),
            keccak256(abi.encodePacked(salt, msg.sender))
        );

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
