// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseHealthCheck } from "./BaseHealthCheck.sol";
import { UniswapV3Swapper } from "./UniswapV3Swapper.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniswapV2Router02 } from "@tokenized-strategy-periphery/interfaces/Uniswap/V2/IUniswapV2Router02.sol";
import { UniswapV3Swapper } from "src/regens/periphery/UniswapV3Swapper.sol";
import { IStaking } from "src/regens/interfaces/ISky.sol";
/// @title yearn-v3-SkyCompounder
/// @author mil0x
/// @notice yearn v3 Strategy that autocompounds staking rewards.
contract SkyCompounder is BaseHealthCheck, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    ///@notice Represents if we should claim rewards. Default to true.
    bool public claimRewards = true;

    ///@notice Represents if we should use UniswapV3 (true) or UniswapV2 (false) to sell rewards. The default is false = UniswapV2.
    bool public useUniV3;

    ///@notice yearn's referral code
    uint16 public referral = 13425;

    ///@notice yearn governance
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    address public immutable staking;
    address public immutable rewardsToken;

    address private constant uniV2router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 router on Mainnet

    // choices for base
    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 private constant ASSET_DUST = 100;

    constructor(
        address _staking,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) BaseHealthCheck(USDS, _name, _management, _keeper, _emergencyAdmin, _donationAddress) {
        require(IStaking(_staking).paused() == false, "paused");
        require(USDS == IStaking(_staking).stakingToken(), "!stakingToken");
        rewardsToken = IStaking(_staking).rewardsToken();
        ERC20(USDS).forceApprove(_staking, type(uint256).max);
        ERC20(rewardsToken).forceApprove(uniV2router, type(uint256).max);
        staking = _staking;
        base = USDS;
        minAmountToSell = 50e18; // Set the min amount for the swapper to sell
    }

    function _deployFunds(uint256 _amount) internal override {
        IStaking(staking).stake(_amount, referral);
    }

    function _freeFunds(uint256 _amount) internal override {
        IStaking(staking).withdraw(_amount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (claimRewards) {
            IStaking(staking).getReward();
            if (useUniV3) {
                // UniV3
                _swapFrom(rewardsToken, address(asset), balanceOfRewards(), 0); // minAmountOut = 0 since we only sell rewards
            } else {
                // UniV2
                _uniV2swapFrom(rewardsToken, address(asset), balanceOfRewards(), 0); // minAmountOut = 0 since we only sell rewards
            }
        }

        uint256 balance = balanceOfAsset();
        if (TokenizedStrategy.isShutdown()) {
            _totalAssets = balance + balanceOfStake();
        } else {
            if (balance > ASSET_DUST) {
                _deployFunds(balance);
            }
            _totalAssets = balanceOfStake();
        }
    }

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        bool paused = IStaking(staking).paused();
        if (paused) return 0;
        return type(uint256).max;
    }

    function _uniV2swapFrom(address _from, address _to, uint256 _amountIn, uint256 _minAmountOut) internal {
        if (_amountIn > minAmountToSell) {
            IUniswapV2Router02(uniV2router).swapExactTokensForTokens(
                _amountIn,
                _minAmountOut,
                _getTokenOutPath(_from, _to),
                address(this),
                block.timestamp
            );
        }
    }

    function _getTokenOutPath(
        address _tokenIn,
        address _tokenOut
    ) internal view virtual returns (address[] memory _path) {
        address _base = base;
        bool isBase = _tokenIn == _base || _tokenOut == _base;
        _path = new address[](isBase ? 2 : 3);
        _path[0] = _tokenIn;

        if (isBase) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = _base;
            _path[2] = _tokenOut;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256 _amount) {
        return ERC20(staking).balanceOf(address(this));
    }

    function balanceOfRewards() public view returns (uint256) {
        return ERC20(rewardsToken).balanceOf(address(this));
    }

    function claimableRewards() public view returns (uint256) {
        return IStaking(staking).earned(address(this));
    }

    //////// EXTERNAL

    /**
     * @notice Set the `claimRewards` bool.
     * @dev For management to set if the strategy should claim rewards during reports.
     * Can be turned off due to rewards being turned off or cause of an issue
     * in either the strategy or compound contracts.
     *
     * @param _claimRewards Bool representing if rewards should be claimed.
     */
    function setClaimRewards(bool _claimRewards) external onlyManagement {
        claimRewards = _claimRewards;
    }

    /**
     * @notice Set fees for UniswapV3 to sell rewardsToken
     * @param _rewardToBase fee reward to base (weth/asset)
     * @param _baseToAsset fee base (weth/asset) to asset
     */
    function setUseUniV3andFees(bool _useUniV3, uint24 _rewardToBase, uint24 _baseToAsset) external onlyManagement {
        useUniV3 = _useUniV3;
        _setUniFees(rewardsToken, base, _rewardToBase);
        _setUniFees(base, address(asset), _baseToAsset);
    }

    /**
     * @notice Set the minimum amount of rewardsToken to sell
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /**
     * @notice Set the base token between USDS, DAI, USDC, or WETH. (Default = USDS)
     * @param _base address of either USDS, DAI, USDC, or WETH.
     * @dev This can be used for management to change which pool
     * to trade reward tokens.
     */
    function setBase(address _base) external onlyManagement {
        if (_base == USDS) {
            base = USDS;
        } else if (_base == DAI) {
            base = DAI;
        } else if (_base == USDC) {
            base = USDC;
        } else if (_base == WETH) {
            base = WETH;
        } else {
            revert("!base in list");
        }
    }

    /**
     * @notice Set the referral code for staking.
     * @param _referral uint16 referral code
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, balanceOfStake());
        _freeFunds(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }
}
