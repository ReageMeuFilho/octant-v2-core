// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TokenizedAllocationMechanism, IBaseAllocationStrategy } from "src/mechanisms/TokenizedAllocationMechanism.sol";

/// @notice Configuration parameters for allocation mechanism initialization
struct AllocationConfig {
    IERC20 asset;
    string name;
    string symbol;
    uint256 votingDelay; // Delay before voting begins (in seconds)
    uint256 votingPeriod; // Duration of voting period (in seconds)
    uint256 quorumShares;
    uint256 timelockDelay; // Delay before redemption begins (in seconds)
    uint256 gracePeriod; // Grace period for redemption (in seconds)
    address owner; // Owner of the mechanism (deployer)
}

/// @title Base Allocation Mechanism - Lightweight Proxy
/// @notice Abstract contract following Yearn V3 pattern for allocation mechanisms
/// @dev Inheritors only need to implement the allocation-specific hooks
abstract contract BaseAllocationMechanism is IBaseAllocationStrategy {
    // ---------- Immutable Storage ----------

    /// @notice Address of the shared TokenizedAllocationMechanism implementation
    address internal immutable tokenizedAllocationAddress;

    /// @notice Underlying asset for the allocation mechanism
    IERC20 internal immutable asset;

    // ---------- Events ----------

    /// @notice Emitted when the allocation mechanism is initialized
    event AllocationMechanismInitialized(
        address indexed implementation,
        address indexed asset,
        string name,
        string symbol
    );

    // ---------- Constructor ----------

    /// @param _implementation Address of the TokenizedAllocationMechanism implementation
    /// @param _config Configuration parameters for the allocation mechanism
    constructor(address _implementation, AllocationConfig memory _config) {
        // Store immutable values
        tokenizedAllocationAddress = _implementation;
        asset = _config.asset;

        // Initialize the TokenizedAllocationMechanism storage via delegatecall
        (bool success, ) = _implementation.delegatecall(
            abi.encodeCall(
                TokenizedAllocationMechanism.initialize,
                (
                    _config.owner, // owner
                    _config.asset,
                    _config.name,
                    _config.symbol,
                    _config.votingDelay,
                    _config.votingPeriod,
                    _config.quorumShares,
                    _config.timelockDelay,
                    _config.gracePeriod
                )
            )
        );
        require(success, "Initialization failed");

        emit AllocationMechanismInitialized(_implementation, address(_config.asset), _config.name, _config.symbol);
    }

    // ---------- Abstract Internal Hooks (Yearn V3 Pattern) ----------

    /// @dev Hook to allow or block registration
    /// @param user Address attempting to register
    /// @return allow True if registration should proceed
    function _beforeSignupHook(address user) internal virtual returns (bool);

    /// @dev Hook to allow or block proposal creation
    /// @param proposer Address proposing
    /// @return allow True if proposing allowed
    function _beforeProposeHook(address proposer) internal view virtual returns (bool);

    /// @dev Hook to calculate new voting power on registration
    /// @param user Address registering
    /// @param deposit Amount of underlying tokens deposited
    /// @return power New voting power assigned
    function _getVotingPowerHook(address user, uint256 deposit) internal view virtual returns (uint256);

    /// @dev Hook to validate existence and integrity of a proposal ID
    /// @param pid Proposal ID to validate
    /// @return valid True if pid is valid and corresponds to a created proposal
    function _validateProposalHook(uint256 pid) internal view virtual returns (bool);

    /// @dev Hook to process a vote
    /// @param pid Proposal ID being voted on
    /// @param voter Address casting the vote
    /// @param choice Vote type (Against/For/Abstain)
    /// @param weight Voting power weight to apply
    /// @param oldPower Voting power before vote
    /// @return newPower Voting power after vote (must be <= oldPower)
    function _processVoteHook(
        uint256 pid,
        address voter,
        TokenizedAllocationMechanism.VoteType choice,
        uint256 weight,
        uint256 oldPower
    ) internal virtual returns (uint256 newPower);

    /// @dev Check if proposal met quorum requirement
    /// @param pid Proposal ID
    /// @return True if proposal has quorum
    function _hasQuorumHook(uint256 pid) internal view virtual returns (bool);

    /// @dev Hook to convert final vote tallies into vault shares to mint
    /// @param pid Proposal ID being queued
    /// @return sharesToMint Number of vault shares to mint for the proposal
    function _convertVotesToShares(uint256 pid) internal view virtual returns (uint256 sharesToMint);

    /// @dev Hook to modify the behavior of finalizeVoteTally
    /// @return allow True if finalization should proceed
    function _beforeFinalizeVoteTallyHook() internal virtual returns (bool);

    /// @dev Hook to fetch the recipient address for a proposal
    /// @param pid Proposal ID being redeemed
    /// @return recipient Address of the recipient for the proposal
    function _getRecipientAddressHook(uint256 pid) internal view virtual returns (address recipient);

    /// @dev Hook to perform custom distribution of shares when a proposal is queued
    /// @dev If this returns (true, assetsTransferred), default share minting is skipped and totalAssets is updated
    /// @param recipient Address of the recipient for the proposal
    /// @param sharesToMint Number of shares to distribute/mint to the recipient
    /// @return handled True if custom distribution was handled, false to use default minting
    /// @return assetsTransferred Amount of assets transferred directly to recipient (to update totalAssets)
    function _requestCustomDistributionHook(
        address recipient,
        uint256 sharesToMint
    ) internal virtual returns (bool handled, uint256 assetsTransferred);

    /// @dev Hook to get the available withdraw limit for a share owner
    /// @dev Default implementation enforces timelock and grace period boundaries
    /// @dev Can be overridden for custom withdrawal limit logic
    /// @return limit Available withdraw limit (type(uint256).max for unlimited, 0 for blocked)
    function _availableWithdrawLimit(address /* shareOwner */) internal view virtual returns (uint256) {
        // Get the global redemption start time
        uint256 globalRedemptionStart = _getGlobalRedemptionStart();

        // If no global redemption time set (not finalized), no withdrawals allowed
        if (globalRedemptionStart == 0) {
            return 0;
        }

        // Check if still in timelock period
        if (block.timestamp < globalRedemptionStart) {
            return 0; // Cannot withdraw during timelock
        }

        // Check if grace period has expired
        uint256 gracePeriod = _getGracePeriod();
        if (block.timestamp > globalRedemptionStart + gracePeriod) {
            return 0; // Cannot withdraw after grace period expires
        }

        // Within valid redemption window - no limit
        return type(uint256).max;
    }

    /// @dev Hook to calculate total assets including any matching pools or custom logic
    /// @return totalAssets Total assets for this allocation mechanism
    function _calculateTotalAssetsHook() internal view virtual returns (uint256);

    // ---------- External Hook Functions (Yearn V3 Pattern) ----------
    // These are called by TokenizedAllocationMechanism via delegatecall
    // and use onlySelf modifier to ensure security

    modifier onlySelf() {
        // In delegatecall context, msg.sender must be address(this) to ensure
        // hooks can only be called via delegatecall from TokenizedAllocationMechanism
        require(msg.sender == address(this), "!self");
        _;
    }

    function beforeSignupHook(address user) external onlySelf returns (bool) {
        return _beforeSignupHook(user);
    }

    function beforeProposeHook(address proposer) external view onlySelf returns (bool) {
        return _beforeProposeHook(proposer);
    }

    function getVotingPowerHook(address user, uint256 deposit) external view onlySelf returns (uint256) {
        return _getVotingPowerHook(user, deposit);
    }

    function validateProposalHook(uint256 pid) external view onlySelf returns (bool) {
        return _validateProposalHook(pid);
    }

    function processVoteHook(
        uint256 pid,
        address voter,
        uint8 choice,
        uint256 weight,
        uint256 oldPower
    ) external onlySelf returns (uint256) {
        return _processVoteHook(pid, voter, TokenizedAllocationMechanism.VoteType(choice), weight, oldPower);
    }

    function hasQuorumHook(uint256 pid) external view onlySelf returns (bool) {
        return _hasQuorumHook(pid);
    }

    function convertVotesToShares(uint256 pid) external view onlySelf returns (uint256) {
        return _convertVotesToShares(pid);
    }

    function beforeFinalizeVoteTallyHook() external onlySelf returns (bool) {
        return _beforeFinalizeVoteTallyHook();
    }

    function getRecipientAddressHook(uint256 pid) external view onlySelf returns (address) {
        return _getRecipientAddressHook(pid);
    }

    function requestCustomDistributionHook(
        address recipient,
        uint256 sharesToMint
    ) external onlySelf returns (bool handled, uint256 assetsTransferred) {
        return _requestCustomDistributionHook(recipient, sharesToMint);
    }

    function availableWithdrawLimit(address shareOwner) external view onlySelf returns (uint256) {
        return _availableWithdrawLimit(shareOwner);
    }

    function calculateTotalAssetsHook() external view onlySelf returns (uint256) {
        return _calculateTotalAssetsHook();
    }

    // ---------- Internal Helpers ----------

    /// @notice Access TokenizedAllocationMechanism interface for internal calls
    /// @dev Uses current contract address since storage is local
    function _tokenizedAllocation() internal view returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(address(this));
    }

    /// @notice Get grace period from configuration
    /// @return Grace period in seconds
    function _getGracePeriod() internal view returns (uint256) {
        return _tokenizedAllocation().gracePeriod();
    }

    /// @dev Get global redemption start timestamp
    function _getGlobalRedemptionStart() internal view returns (uint256) {
        return _tokenizedAllocation().globalRedemptionStart();
    }

    // ---------- Fallback Function ----------

    /// @notice Delegates all undefined function calls to TokenizedAllocationMechanism
    /// @dev This enables the proxy pattern where shared logic lives in the implementation
    fallback() external payable virtual {
        address _impl = tokenizedAllocationAddress;
        assembly {
            // Copy calldata to memory
            calldatacopy(0, 0, calldatasize())

            // Delegatecall to implementation contract
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)

            // Copy return data
            returndatacopy(0, 0, returndatasize())

            // Handle result
            switch result
            case 0 {
                // Delegatecall failed, revert with error data
                revert(0, returndatasize())
            }
            default {
                // Delegatecall succeeded, return data
                return(0, returndatasize())
            }
        }
    }

    /// @notice Receive function to accept ETH
    receive() external payable virtual {}

    // ---------- View Helpers for Inheritors ----------

    /// @notice Get the current proposal count
    /// @dev Helper for concrete implementations to access storage
    function _getProposalCount() internal view returns (uint256) {
        return _tokenizedAllocation().getProposalCount();
    }

    /// @notice Check if a proposal exists
    /// @dev Helper for concrete implementations
    function _proposalExists(uint256 pid) internal view returns (bool) {
        return pid > 0 && pid <= _getProposalCount();
    }

    /// @notice Get proposal details
    /// @dev Helper for concrete implementations
    function _getProposal(uint256 pid) internal view returns (TokenizedAllocationMechanism.Proposal memory) {
        return _tokenizedAllocation().proposals(pid);
    }

    /// @notice Get voting power for an address
    /// @dev Helper for concrete implementations
    function _getVotingPower(address user) internal view returns (uint256) {
        return _tokenizedAllocation().votingPower(user);
    }

    /// @notice Get quorum shares requirement
    /// @dev Helper for concrete implementations
    function _getQuorumShares() internal view returns (uint256) {
        return _tokenizedAllocation().quorumShares();
    }
}
