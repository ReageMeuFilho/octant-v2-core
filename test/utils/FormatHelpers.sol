// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title FormatHelpers
 * @notice Reusable formatting utilities for test output
 */
library FormatHelpers {
    function padLeft(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);
        uint256 padding = length - strBytes.length;

        // Fill with spaces
        for (uint256 i = 0; i < padding; i++) {
            result[i] = " ";
        }

        // Copy string
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padding + i] = strBytes[i];
        }

        return string(result);
    }

    function padRight(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);

        // Copy string first
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[i] = strBytes[i];
        }

        // Fill remaining with spaces
        for (uint256 i = strBytes.length; i < length; i++) {
            result[i] = " ";
        }

        return string(result);
    }

    function padLeftZero(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);
        uint256 padding = length - strBytes.length;

        // Fill with zeros
        for (uint256 i = 0; i < padding; i++) {
            result[i] = "0";
        }

        // Copy string
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padding + i] = strBytes[i];
        }

        return string(result);
    }

    function formatDuration(uint256 duration) internal pure returns (string memory) {
        uint256 durationDays = duration / 1 days;
        if (durationDays < 10) return string(abi.encodePacked("    ", toString(durationDays), " day "));
        if (durationDays < 100) return string(abi.encodePacked("   ", toString(durationDays), " days"));
        if (durationDays < 1000) return string(abi.encodePacked("  ", toString(durationDays), " days"));
        return string(abi.encodePacked(" ", toString(durationDays), " days"));
    }

    function formatDurationFixed(uint256 duration) internal pure returns (string memory) {
        uint256 durationDays = duration / 1 days;
        string memory dayStr = toString(durationDays);
        string memory suffix = durationDays == 1 ? " day " : " days";
        return padLeft(string(abi.encodePacked(dayStr, suffix)), 12);
    }

    function formatNumber(uint256 number) internal pure returns (string memory) {
        return toString(number);
    }

    function formatLargeNumber(uint256 number) internal pure returns (string memory) {
        if (number >= 1e12) {
            return
                string(
                    abi.encodePacked(
                        toString(number / 1e12),
                        ",",
                        padLeftZero(toString((number % 1e12) / 1e9), 3),
                        ",",
                        padLeftZero(toString((number % 1e9) / 1e6), 3),
                        ",",
                        padLeftZero(toString((number % 1e6) / 1e3), 3),
                        ",",
                        padLeftZero(toString(number % 1e3), 3)
                    )
                );
        } else if (number >= 1e9) {
            return
                string(
                    abi.encodePacked(
                        toString(number / 1e9),
                        ",",
                        padLeftZero(toString((number % 1e9) / 1e6), 3),
                        ",",
                        padLeftZero(toString((number % 1e6) / 1e3), 3),
                        ",",
                        padLeftZero(toString(number % 1e3), 3)
                    )
                );
        } else if (number >= 1e6) {
            return
                string(
                    abi.encodePacked(
                        toString(number / 1e6),
                        ",",
                        padLeftZero(toString((number % 1e6) / 1e3), 3),
                        ",",
                        padLeftZero(toString(number % 1e3), 3)
                    )
                );
        } else if (number >= 1e3) {
            return string(abi.encodePacked(toString(number / 1e3), ",", padLeftZero(toString(number % 1e3), 3)));
        } else {
            return toString(number);
        }
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
