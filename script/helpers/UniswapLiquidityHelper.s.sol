/* SPDX-License-Identifier: GPL-3.0 */
pragma solidity ^0.8.23;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
// import '@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol';

contract UniswapLiquidityHelper is IERC721Receiver {

    error UniswapLiquidityHelper__MustBeOwner();

    address public immutable contractOwner;
    address public immutable token0Address;
    address public immutable token1Address;

    uint24 public immutable poolFee;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits;
    mapping(uint24 => int24) public override feeAmountTickSpacing;

    constructor(address token0Address_, address token1Address_, address nonfungiblePositionManager_, uint24 poolFee_) {
        contractOwner = msg.sender;
        token0Address = token0Address_;
        token1Address = token1Address_;
        nonfungiblePositionManager = INonfungiblePositionManager(nonfungiblePositionManager_);
        poolFee = poolFee_;

        feeAmountTickSpacing[500] = 10;
        feeAmountTickSpacing[3000] = 60;
        feeAmountTickSpacing[10000] = 200;
    }

    function onERC721Received(
                              address operator,
                              address,
                              uint256 tokenId,
                              bytes calldata
    ) external override returns (bytes4) {
        // get position information
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) =
            nonfungiblePositionManager.positions(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }
    /// @notice Calls the mint function defined in periphery, mints the same amount of each token
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(uint256 amountToMint0ETH_, uint256 amountToMint1ETH_)
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) {
        uint256 amount0ToMint = 1 ether * amountToMint0ETH_;
        uint256 amount1ToMint = 1 ether * amountToMint1ETH_;

        // Approve the position manager
        TransferHelper.safeApprove(token0Address, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(token1Address, address(nonfungiblePositionManager), amount1ToMint);

        int24 tickSpacing = feeAmountTickSpacing[poolFee];
        int24 tickLowerRounded = nearestUsableTick(TickMath.MIN_TICK, tickSpacing);
        int24 tickUpperRounded = nearestUsableTick(TickMath.MAX_TICK, tickSpacing);

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: token0Address,
                token1: token1Address,
                fee: poolFee,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Note that the pool defined by GLM/WETH and fee tier 1.0% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0Address, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(token0Address, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1Address, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(token1Address, msg.sender, refund1);
        }
    }

    function nearestUsableTick(int24 tick_, uint24 tickSpacing) internal pure returns (int24 result) {
        result = int24(divRound(int128(tick_), int128(int24(tickSpacing)))) * int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }


    function returnFunds(uint256 token0Amount, uint256 token1Amount) public {
        if (msg.sender != contractOwner) {
            revert UniswapLiquidityHelper__MustBeOwner();
        } 
        TransferHelper.safeTransfer(token0Address, contractOwner, token0Amount);
        TransferHelper.safeTransfer(token1Address, contractOwner, token1Amount);
    }
}