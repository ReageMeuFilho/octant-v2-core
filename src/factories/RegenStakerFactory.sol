// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CREATE3 } from "solady/utils/CREATE3.sol";
import { IERC20, IERC20Staking, IWhitelist, IEarningPowerCalculator } from "src/regen/RegenStaker.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Delegates } from "staker/interfaces/IERC20Delegates.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/// @title RegenStaker Factory with Automatic Variant Detection
/// @notice Deploys RegenStaker contracts with automatic token capability detection
/// @author [Golem Foundation](https://golem.foundation)
contract RegenStakerFactory {
    uint256 private constant EVM_WORD_SIZE = 32;
    uint256 private constant INTERFACE_CHECK_GAS_LIMIT = 30000;

    // Reason codes for VariantDetected event
    bytes32 public constant REASON_SUPPORTS_DELEGATION = keccak256("SUPPORTS_DELEGATION");
    bytes32 public constant REASON_SUPPORTS_PERMIT_NO_DELEGATION = keccak256("SUPPORTS_PERMIT_NO_DELEGATION");
    bytes32 public constant REASON_BASIC_ERC20 = keccak256("BASIC_ERC20");

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
    event VariantDetected(IERC20 indexed token, RegenStakerVariant variant, bytes32 reasonCode);

    error InvalidBytecode();

    /// @notice Deploy RegenStaker with automatic variant detection
    /// @param params Staker configuration parameters
    /// @param salt Deployment salt for deterministic addressing
    /// @param codePermit Bytecode for NO_DELEGATION variant
    /// @param codeStaking Bytecode for ERC20_STAKING variant
    /// @return stakerAddress Address of deployed contract
    /// @return variant Variant that was selected and deployed
    function createStaker(
        CreateStakerParams calldata params,
        bytes32 salt,
        bytes calldata codePermit,
        bytes calldata codeStaking
    ) external returns (address stakerAddress, RegenStakerVariant variant) {
        if (codePermit.length == 0 || codeStaking.length == 0) revert InvalidBytecode();

        variant = detectStakerVariant(params.stakeToken);
        bytes memory bytecode = variant == RegenStakerVariant.ERC20_STAKING ? codeStaking : codePermit;
        stakerAddress = _deployStaker(params, salt, bytecode, variant);
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
    ) external returns (address stakerAddress) {
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
    ) external returns (address stakerAddress) {
        if (code.length == 0) revert InvalidBytecode();
        stakerAddress = _deployStaker(params, salt, code, RegenStakerVariant.ERC20_STAKING);
    }

    /// @notice Detect optimal RegenStaker variant for token
    /// @param token Token to analyze for capabilities
    /// @return variant Recommended staker variant
    function detectStakerVariant(IERC20 token) public returns (RegenStakerVariant variant) {
        bool supportsDelegate = _supportsInterface(token, type(IERC20Delegates).interfaceId);

        if (supportsDelegate) {
            variant = RegenStakerVariant.ERC20_STAKING;
            emit VariantDetected(token, variant, REASON_SUPPORTS_DELEGATION);
        } else {
            variant = RegenStakerVariant.NO_DELEGATION;
            bool supportsPermit = _supportsInterface(token, type(IERC20Permit).interfaceId);

            if (supportsPermit) {
                emit VariantDetected(token, variant, REASON_SUPPORTS_PERMIT_NO_DELEGATION);
            } else {
                emit VariantDetected(token, variant, REASON_BASIC_ERC20);
            }
        }

        return variant;
    }

    /// @notice Get recommended variant without events
    /// @param token Token to analyze for capabilities
    /// @return variant Recommended staker variant
    function getRecommendedVariant(IERC20 token) external view returns (RegenStakerVariant variant) {
        return
            _supportsInterface(token, type(IERC20Delegates).interfaceId)
                ? RegenStakerVariant.ERC20_STAKING
                : RegenStakerVariant.NO_DELEGATION;
    }

    /// @notice Predict deterministic deployment address
    /// @param salt Deployment salt
    /// @param deployer Address that will deploy
    /// @return Predicted contract address
    function predictStakerAddress(bytes32 salt, address deployer) external view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(abi.encodePacked(salt, deployer)));
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

    function _supportsInterface(IERC20 contractAddr, bytes4 interfaceId) internal view returns (bool) {
        // First try ERC165 detection using OpenZeppelin's robust implementation
        if (ERC165Checker.supportsInterface(address(contractAddr), interfaceId)) {
            return true;
        }

        // Fallback to manual detection for interfaces that might not be properly declared via ERC165
        if (interfaceId == type(IERC20Delegates).interfaceId) {
            return _checkDelegatesSupport(contractAddr);
        } else if (interfaceId == type(IERC20Permit).interfaceId) {
            return _checkPermitSupport(contractAddr);
        }

        return false;
    }

    function _checkDelegatesSupport(IERC20 contractAddr) internal view returns (bool) {
        (bool success, bytes memory data) = address(contractAddr).staticcall{ gas: INTERFACE_CHECK_GAS_LIMIT }(
            abi.encodeWithSignature("delegates(address)", address(0))
        );

        return success && data.length == EVM_WORD_SIZE;
    }

    function _checkPermitSupport(IERC20 contractAddr) internal view returns (bool) {
        (bool success1, bytes memory data1) = address(contractAddr).staticcall{ gas: INTERFACE_CHECK_GAS_LIMIT }(
            abi.encodeWithSignature("nonces(address)", address(0))
        );

        if (!success1 || data1.length != EVM_WORD_SIZE) {
            return false;
        }

        (bool success2, bytes memory data2) = address(contractAddr).staticcall{ gas: INTERFACE_CHECK_GAS_LIMIT }(
            abi.encodeWithSignature("DOMAIN_SEPARATOR()")
        );

        return success2 && data2.length == EVM_WORD_SIZE;
    }
}
