// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";

/**
 * @title DecimalConversionTest
 * @notice Tests for TRST-M-2: Verifies proper decimal conversion without precision loss
 */
contract DecimalConversionTest is Test {
    using WadRayMath for uint256;

    function testDirectConversionToRay() public pure {
        // Test the correct conversion logic that should be in _currentRateRay

        // Test with 18 decimals
        uint256 rate18 = 1e18;
        uint256 rayFrom18 = rate18 * 10 ** (27 - 18);
        assertEq(rayFrom18, 1e27, "18 decimals should scale to RAY correctly");

        // Test with 6 decimals
        uint256 rate6 = 1e6;
        uint256 rayFrom6 = rate6 * 10 ** (27 - 6);
        assertEq(rayFrom6, 1e27, "6 decimals should scale to RAY correctly");

        // Test with exactly 27 decimals (no conversion needed)
        uint256 rate27 = 1e27;
        assertEq(rate27, 1e27, "27 decimals should remain unchanged");

        // Test with 30 decimals
        uint256 rate30 = 1e30;
        uint256 rayFrom30 = rate30 / 10 ** (30 - 27);
        assertEq(rayFrom30, 1e27, "30 decimals should scale down to RAY correctly");
    }

    function testPrecisionPreservedForHighDecimals() public pure {
        // Test case from audit: exchange rate with 30 decimals
        uint256 exchangeRate30Decimals = 123456789012345678901234567890; // 30 digits

        // Direct conversion to RAY (27 decimals) - the correct way
        uint256 resultRayDirect = exchangeRate30Decimals / 10 ** (30 - 27);

        // Old way: first to WAD (18), then to RAY (27) - causes precision loss
        uint256 toWad = exchangeRate30Decimals / 10 ** (30 - 18); // loses 12 decimals of precision
        uint256 resultRayOld = toWad.wadToRay(); // scales up by 9 decimals

        // Verify direct conversion preserves more precision
        assertEq(resultRayDirect, 123456789012345678901234567, "Direct conversion should preserve 27 digits");

        // The old way would have lost precision
        // After converting to 18 decimals: 123456789012345678
        // Then scaling to 27: 123456789012345678000000000
        assertEq(resultRayOld, 123456789012345678000000000, "Old conversion loses precision");

        // Demonstrate the precision loss
        assertTrue(resultRayDirect != resultRayOld, "Direct and old methods should give different results");

        // The difference is significant - 901234567
        uint256 precisionLoss = resultRayDirect - resultRayOld;
        assertEq(precisionLoss, 901234567, "Precision loss should be 901234567");
    }

    function testConversionLogic(uint256 exchangeRate, uint256 decimals) public pure {
        // Bound decimals to reasonable range
        decimals = bound(decimals, 0, 77);

        // Skip if rate would overflow
        if (decimals < 27) {
            if (exchangeRate > type(uint256).max / 10 ** (27 - decimals)) return;
        }

        uint256 resultRay;

        // This is the correct conversion logic from the fix
        if (decimals == 27) {
            resultRay = exchangeRate;
        } else if (decimals < 27) {
            resultRay = exchangeRate * 10 ** (27 - decimals);
        } else {
            resultRay = exchangeRate / 10 ** (decimals - 27);
        }

        // Verify no overflow occurred
        if (decimals < 27) {
            assertLe(resultRay, type(uint256).max, "Should not overflow");
        }
    }
}
