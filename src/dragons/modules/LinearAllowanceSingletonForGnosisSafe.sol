// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);
}

event AllowanceSet(address indexed safe, address indexed delegate, address indexed token, uint96 dripRatePerDay);
event AllowanceTransferred(
    address indexed safe,
    address indexed delegate,
    address indexed token,
    address to,
    uint112 amount
);

error NoAllowanceToTransfer(address safe, address delegate, address token);
error TransferFailed(address safe, address delegate, address token);
error BadERC20(address token);

/// @title LinearAllowance
/// @notice A module that allows a delegate to transfer allowances from a safe to a recipient.
contract LinearAllowanceSingletonForGnosisSafe is ReentrancyGuard {
    // Compress by trimming 32 le Lossy compression. Use values that are multiples of 2^32 to avoid precision loss.
    uint8 public constant NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM = 32;
    address public constant NATIVE_TOKEN = 0x0000000000000000000000000000000000000000;

    // Maximum accumulation period is 2^(80-64) days, which is around 89 years.
    struct LinearAllowance {
        uint64 dripRatePerDay; // 32-bits compression. Decompressed size is 96 bits.
        uint80 totalUnspent; // 32-bits compression. Decompressed size is 112 bits.
        uint80 totalSpent; // 32-bits compression. Decompressed size is 112 bits.
        uint32 lastBookedAt; // 0 is a special case for uninitialized allowance. Overflows in year 2106 in Gregorian calendar.
    }

    mapping(address => mapping(address => mapping(address => LinearAllowance))) public allowances; // safe -> delegate -> token -> allowance

    function decompress80to112(uint80 input) internal pure returns (uint112) {
        return uint112(input) << NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM;
    }

    function decompress64to96(uint64 input) internal pure returns (uint96) {
        return uint96(input) << NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM;
    }

    function compress112to80(uint112 input) internal pure returns (uint80) {
        return uint80(input >> NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM);
    }

    function compress96to64(uint96 input) internal pure returns (uint64) {
        return uint64(input >> NUMBER_OF_LEAST_SIGNIFICANT_BITS_TO_TRIM);
    }

    function trimLast32BitsOf256(uint256 input) public pure returns (uint256) {
        // Mask to preserve all bits except the last 32 bits
        uint256 mask = uint256(0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_00000000);
        return input & mask;
    }

    function updateAllowance(LinearAllowance storage a) internal {
        if (a.lastBookedAt != 0) {
            uint256 timeElapsed = block.timestamp - a.lastBookedAt;
            uint256 daysElapsed = timeElapsed / 1 days;

            // Decompress dripRatePerDay before calculation
            uint96 decompressedDripRatePerDay = decompress64to96(a.dripRatePerDay);

            // Decompress totalUnspent, add the accrued amount, then compress again
            uint112 decompressedTotalUnspent = decompress80to112(a.totalUnspent);
            uint112 accrued = uint112(daysElapsed) * decompressedDripRatePerDay;
            uint112 newTotalUnspent = decompressedTotalUnspent + accrued;

            // Compress before storing
            a.totalUnspent = compress112to80(newTotalUnspent);
            a.lastBookedAt = uint32(block.timestamp);
        } else {
            // Special case for uninitialized allowance
            a.lastBookedAt = uint32(block.timestamp);
        }
    }

    /// @notice Set the allowance for a delegate. To revoke, set dripRatePerDay to 0. Revoking will not cancel any unspent allowance.
    /// @dev dripRatePerDay is compressed to 64 bits by trimming the least significant 32 bits.
    /// @param delegate The delegate to set the allowance for.
    /// @param token The token to set the allowance for. 0x0 is ETH.
    /// @param dripRatePerDay The drip rate per day for the allowance. Input a value that is a multiple of 2^32 to avoid precision loss.
    function setAllowance(address delegate, address token, uint96 dripRatePerDay) external {
        LinearAllowance storage a = allowances[msg.sender][delegate][token];
        updateAllowance(a);
        a.dripRatePerDay = compress96to64(dripRatePerDay);

        emit AllowanceSet(msg.sender, delegate, token, dripRatePerDay);
    }

    /// @notice Execute a transfer of the allowance.
    /// @dev msg.sender is the delegate.
    /// @param safe The address of the safe.
    /// @param token The address of the token.
    /// @param to The address of the beneficiary.
    /// @return amount The amount that was actually transferred
    function executeAllowanceTransfer(
        address safe,
        address token,
        address payable to
    ) external nonReentrant returns (uint256) {
        LinearAllowance storage a = allowances[safe][msg.sender][token];
        updateAllowance(a);

        uint112 decompressedTotalUnspent = decompress80to112(a.totalUnspent);
        require(decompressedTotalUnspent > 0, NoAllowanceToTransfer(safe, msg.sender, token));

        uint112 trimmedSafeBalance = uint112(trimLast32BitsOf256(address(safe).balance));

        uint112 transferAmount;

        if (token == NATIVE_TOKEN) {
            transferAmount = decompressedTotalUnspent <= trimmedSafeBalance
                ? decompressedTotalUnspent
                : trimmedSafeBalance;

            if (transferAmount > 0) {
                require(
                    ISafe(payable(safe)).execTransactionFromModule(to, transferAmount, "", Enum.Operation.Call),
                    TransferFailed(safe, msg.sender, token)
                );
            }
        } else {
            try IERC20(token).balanceOf(safe) returns (uint256 tokenBalance) {
                uint112 trimmedTokenBalance = uint112(trimLast32BitsOf256(tokenBalance));
                transferAmount = decompressedTotalUnspent <= trimmedTokenBalance
                    ? decompressedTotalUnspent
                    : trimmedTokenBalance;

                if (transferAmount > 0) {
                    bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, transferAmount);
                    require(
                        ISafe(payable(safe)).execTransactionFromModule(token, 0, data, Enum.Operation.Call),
                        TransferFailed(safe, msg.sender, token)
                    );
                }
            } catch {
                revert BadERC20(token);
            }
        }

        uint112 decompressedTotalSpent = decompress80to112(a.totalSpent);

        // Update with transferred amount
        decompressedTotalSpent += transferAmount;
        decompressedTotalUnspent -= transferAmount;

        // Compress before storing back
        a.totalSpent = compress112to80(decompressedTotalSpent);
        a.totalUnspent = compress112to80(decompressedTotalUnspent);

        emit AllowanceTransferred(safe, msg.sender, token, to, transferAmount);

        return transferAmount;
    }

    /// @notice Get the decompressed allowance data for a token.
    /// @param safe The address of the safe.
    /// @param delegate The address of the delegate.
    /// @param token The address of the token.
    /// @return allowanceData [dripRatePerDay, totalUnspent, totalSpent, lastBookedAt]
    function getTokenAllowanceData(
        address safe,
        address delegate,
        address token
    ) public view returns (uint112[4] memory allowanceData) {
        LinearAllowance memory allowance = allowances[safe][delegate][token];
        allowanceData = [
            uint112(decompress64to96(allowance.dripRatePerDay)),
            decompress80to112(allowance.totalUnspent),
            decompress80to112(allowance.totalSpent),
            uint112(allowance.lastBookedAt)
        ];
    }

    /// @notice Get the total unspent allowance for a token.
    /// @param safe The address of the safe.
    /// @param delegate The address of the delegate.
    /// @param token The address of the token.
    /// @return totalAllowanceAsOfNow The total unspent allowance as of now.
    function getTotalUnspent(address safe, address delegate, address token) public view returns (uint112) {
        LinearAllowance memory allowance = allowances[safe][delegate][token];

        if (allowance.lastBookedAt == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - allowance.lastBookedAt;
        uint256 daysElapsed = timeElapsed / 1 days;

        // Decompress both values
        uint96 decompressedDripRatePerDay = decompress64to96(allowance.dripRatePerDay);
        uint112 decompressedTotalUnspent = decompress80to112(allowance.totalUnspent);

        // Calculate using decompressed values
        uint112 totalAllowanceAsOfNow = decompressedTotalUnspent + uint112(decompressedDripRatePerDay * daysElapsed);

        return totalAllowanceAsOfNow;
    }
}
