// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IBaseImpactStrategy {
    function tokenizedStrategyAddress() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(address _owner) external view returns (uint256);

    function availableWithdrawLimit(address _owner) external view returns (uint256);

    //function mintWarbonds(uint256 _assets) external;

    function shutdownWithdraw(uint256 _amount) external;

    function convertToVotes(uint256 _assets) external view returns (uint256);

    function processVote(uint256 projectId, uint256 contribution, uint256 voteWeight) external;

    function tally(uint256 projectId) external view returns (uint256 projectShares, uint256 totalShares);

    function finalize(uint256 totalShares) external view returns (uint256 finalizedTotalShares);
}
