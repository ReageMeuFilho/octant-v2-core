// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { DragonBaseStrategy, ERC20 } from "src/dragons/vaults/DragonBaseStrategy.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IBaseStrategy } from "src/interfaces/IBaseStrategy.sol";
import { IMantleStaking } from "src/interfaces/IMantleStaking.sol";
import { IMantleMehTokenizedStrategy } from "src/interfaces/IMantleMehTokenizedStrategy.sol";
import { ITokenizedStrategy } from "src/interfaces/ITokenizedStrategy.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDragonTokenizedStrategy } from "src/interfaces/IDragonTokenizedStrategy.sol";
import { TokenizedStrategy } from "src/dragons/vaults/TokenizedStrategy.sol";
import { TokenizedStrategy__InvalidMaxLoss, ZeroAddress } from "src/errors.sol";
import { IDragonTokenizedStrategy } from "src/interfaces/IDragonTokenizedStrategy.sol";

contract MantleMehTokenizedStrategy is DragonBaseStrategy, IMantleMehTokenizedStrategy, ReentrancyGuard {
    /* @inheritdoc IMantleMehTokenizedStrategy */
    address public constant override MANTLE_STAKING = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;

    /* @inheritdoc IMantleMehTokenizedStrategy */
    address public constant override METH_TOKEN = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;

    /* User unstake requests mapping */
    mapping(address => uint256[]) public override userUnstakeRequests;

    /* Unstake request claimed mapping */
    mapping(uint256 => bool) public override unstakeRequestClaimed;

    /* @inheritdoc DragonBaseStrategy */
    function setUp(bytes memory initializeParams) public override initializer {
        // ETH is the asset
        address _asset = ETH;

        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address _tokenizedStrategyImplementation,
            address _management,
            address _keeper,
            address _dragonRouter,
            uint256 _maxReportDelay,
            address _regenGovernance
        ) = abi.decode(data, (address, address, address, address, uint256, address));

        __Ownable_init(msg.sender);
        string memory _name = "Octant Mantle ETH Strategy";
        __BaseStrategy_init(
            _tokenizedStrategyImplementation,
            _asset,
            _owner,
            _management,
            _keeper,
            _dragonRouter,
            _maxReportDelay,
            _name,
            _regenGovernance
        );

        IERC20(METH_TOKEN).approve(MANTLE_STAKING, type(uint256).max);

        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);
    }

    /* @inheritdoc IMantleMehTokenizedStrategy */
    function claimUnstakeRequest(uint256 requestId, address receiver) external nonReentrant {
        // Check if request belongs to caller
        bool found = false;
        uint256[] storage userRequests = userUnstakeRequests[msg.sender];

        for (uint256 i = 0; i < userRequests.length; i++) {
            if (userRequests[i] == requestId) {
                found = true;
                break;
            }
        }
        require(found, NotYourRequest());

        require(!unstakeRequestClaimed[requestId], RequestAlreadyClaimed());

        // Check if request is finalized and filled
        (bool finalized, uint256 filledAmount) = IMantleStaking(MANTLE_STAKING).unstakeRequestInfo(requestId);

        require(finalized && filledAmount > 0, RequestNotReady());

        // Claim the ETH from Mantle
        IMantleStaking(MANTLE_STAKING).claimUnstakeRequest(requestId);

        // Mark as claimed
        unstakeRequestClaimed[requestId] = true;

        // Send ETH to the receiver
        (bool success, ) = receiver.call{ value: filledAmount }("");
        require(success, ETHTransferFailed());
    }

    /* @inheritdoc IMantleMehTokenizedStrategy */
    function availableDepositLimit(address _user) public view override returns (uint256) {
        uint256 actualLimit = super.availableDepositLimit(_user);
        uint256 mantleLimit = IMantleStaking(MANTLE_STAKING).maximumDepositAmount();
        return Math.min(actualLimit, mantleLimit);
    }

    /* @inheritdoc IMantleMehTokenizedStrategy */
    function convertAssetsToMETH(uint256 ethAmount) public view returns (uint256) {
        return IMantleStaking(MANTLE_STAKING).ethToMETH(ethAmount);
    }

    /* @inheritdoc IMantleMehTokenizedStrategy */
    function convertMETHToAssets(uint256 methAmount) public view returns (uint256) {
        return IMantleStaking(MANTLE_STAKING).mETHToETH(methAmount);
    }

    /* @inheritdoc IMantleMehTokenizedStrategy */
    function getUserUnstakeRequests(
        address user
    ) external view override returns (uint256[] memory, bool[] memory, uint256[] memory) {
        uint256[] storage requests = userUnstakeRequests[user];
        bool[] memory finalized = new bool[](requests.length);
        uint256[] memory filledAmounts = new uint256[](requests.length);

        for (uint256 i = 0; i < requests.length; i++) {
            (finalized[i], filledAmounts[i]) = IMantleStaking(MANTLE_STAKING).unstakeRequestInfo(requests[i]);
        }

        return (requests, finalized, filledAmounts);
    }

    /* Internal function to deploy funds by staking ETH
     * @param _amount The amount of ETH to stake
     */
    function _deployFunds(uint256 _amount) internal override {
        if (_amount > 0) {
            // Convert ETH to mETH by staking
            IMantleStaking(MANTLE_STAKING).stake{ value: _amount }();
        }
    }

    /* Internal function for emergency withdrawal
     * @param _amount The amount to withdraw in emergency (unused)
     */
    function _emergencyWithdraw(uint256 /*_amount*/) internal override {
        // In emergency, try to submit unstake request for the entire balance
        uint256 mEthBalance = IERC20(METH_TOKEN).balanceOf(address(this));
        uint256 expectedEth = convertMETHToAssets(mEthBalance);

        uint256 requestId = IMantleStaking(MANTLE_STAKING).unstakeRequest(uint128(mEthBalance), uint128(expectedEth));

        // todo: review what makes most sense here
        userUnstakeRequests[owner()].push(requestId);
    }

    /* Internal function to free funds by submitting unstake request
     * @param _amount The amount of ETH to free
     * todo discuss Flow:
     * 1. User calls withdraw/redeem on TokenizedStrategy with MAX_BPS as maxLoss
     * 2. TokenizedStrategy calls _freeFunds internally
     * 3. We convert ETH amount to mETH equivalent based on exchange rate
     * 4. We submit unstake request to Mantle Staking
     * 5. We store requestId mapped to original caller for later claiming
     * @dev Note: Users must use MAX_BPS (10,000) as maxLoss parameter when withdrawing
     * to ensure transaction doesn't revert from potential slippage as the funds are not unstaked immediately (tbd)
     */
    function _freeFunds(uint256 _amount) internal virtual override {
        // Convert to mETH equivalent
        uint256 methAmount = convertAssetsToMETH(_amount);

        // Submit unstake request
        uint256 requestId = IMantleStaking(MANTLE_STAKING).unstakeRequest(
            uint128(methAmount),
            uint128(_amount) // Minimum ETH amount expected
        );

        // fetch the receiver from TokenizedStrategy
        address receiver = ITokenizedStrategy(address(this)).getReceiver();
        userUnstakeRequests[receiver].push(requestId);
    }

    /* Internal function to harvest and report total value
     * @return The total value of the strategy in ETH
     */
    // todo: discuss what we should do since it is a 2 steps process / show we initiate the unstake request?
    // We don't unstake during harvest because:
    // 1. Mantle unstaking is a multi-step process with delays
    // 2. We can accurately calculate ETH value via the exchange rate
    // 3. Unstaking would reduce yield and create operational complexity
    function _harvestAndReport() internal override returns (uint256) {
        // Get current balance of mETH
        uint256 mEthBalance = IERC20(METH_TOKEN).balanceOf(address(this));

        // Calculate ETH value based on exchange rate
        uint256 ethValue = convertMETHToAssets(mEthBalance);

        // Add any ETH we have in the contract
        ethValue += address(this).balance;

        return ethValue;
    }

    /* Internal function to handle tending funds
     * @param _idle The amount of idle funds (unused)
     */
    function _tend(uint256 /*_idle*/) internal override {
        // only accessible from the keepers
        if (address(this).balance > 0) {
            IMantleStaking(MANTLE_STAKING).stake{ value: address(this).balance }();
        }
    }

    /* Internal function to determine if tending is needed
     * @return Always returns true to enable tending
     */
    function _tendTrigger() internal pure override returns (bool) {
        return true;
    }
}
