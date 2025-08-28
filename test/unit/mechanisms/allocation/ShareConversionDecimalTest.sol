// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { SimpleVotingMechanism } from "test/mocks/SimpleVotingMechanism.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 with configurable decimals
contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title Share Conversion Decimal Test
/// @notice Tests that convertToShares() and convertToAssets() handle decimal differences correctly
/// @dev Demonstrates the fix for the bug where these functions assumed 1:1 conversion when totalSupply == 0
contract ShareConversionDecimalTest is Test {
    AllocationMechanismFactory factory;
    MockToken token6; // USDC-like (6 decimals)
    MockToken token8; // WBTC-like (8 decimals)
    MockToken token18; // ETH-like (18 decimals)
    MockToken token24; // Hypothetical high-precision token (24 decimals)

    SimpleVotingMechanism mechanism6;
    SimpleVotingMechanism mechanism8;
    SimpleVotingMechanism mechanism18;
    SimpleVotingMechanism mechanism24;

    function _tokenized(address _mechanism) internal pure returns (TokenizedAllocationMechanism) {
        return TokenizedAllocationMechanism(_mechanism);
    }

    function setUp() public {
        factory = new AllocationMechanismFactory();

        // Create tokens with different decimal configurations
        token6 = new MockToken("USDC", "USDC", 6);
        token8 = new MockToken("WBTC", "WBTC", 8);
        token18 = new MockToken("ETH", "ETH", 18);
        token24 = new MockToken("HighPrec", "HP", 24);

        // Deploy mechanisms for each token type
        mechanism6 = _deployMechanism(token6);
        mechanism8 = _deployMechanism(token8);
        mechanism18 = _deployMechanism(token18);
        mechanism24 = _deployMechanism(token24);
    }

    function _deployMechanism(MockToken token) internal returns (SimpleVotingMechanism) {
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(token)),
            name: string.concat("Mechanism ", token.symbol()),
            symbol: string.concat("M", token.symbol()),
            votingDelay: 100,
            votingPeriod: 1000,
            quorumShares: 100 ether, // In 18 decimals
            timelockDelay: 1 days,
            gracePeriod: 7 days,
            owner: address(this)
        });

        address mechanismAddr = factory.deploySimpleVotingMechanism(config);
        return SimpleVotingMechanism(payable(mechanismAddr));
    }

    /// @notice Test convertToShares when totalSupply == 0
    /// @dev Verifies proper decimal scaling from asset decimals to 18-decimal shares
    function testConvertToShares_ZeroSupply_DecimalHandling() public view {
        console.log("=== convertToShares Test - Zero Supply ===");

        // Test amounts: 1000 tokens in each token's native decimals
        uint256 amount6 = 1000 * 10 ** 6; // 1000 USDC
        uint256 amount8 = 1000 * 10 ** 8; // 1000 WBTC
        uint256 amount18 = 1000 * 10 ** 18; // 1000 ETH
        uint256 amount24 = 1000 * 10 ** 24; // 1000 HighPrec

        // Convert to shares (should all result in equivalent 18-decimal amounts)
        uint256 shares6 = _tokenized(address(mechanism6)).convertToShares(amount6);
        uint256 shares8 = _tokenized(address(mechanism8)).convertToShares(amount8);
        uint256 shares18 = _tokenized(address(mechanism18)).convertToShares(amount18);
        uint256 shares24 = _tokenized(address(mechanism24)).convertToShares(amount24);

        console.log("Asset amounts (native decimals):");
        console.log("  6-decimal token:", amount6);
        console.log("  8-decimal token:", amount8);
        console.log("  18-decimal token:", amount18);
        console.log("  24-decimal token:", amount24);

        console.log("\nConverted to shares (18 decimals):");
        console.log("  From 6-decimal:", shares6);
        console.log("  From 8-decimal:", shares8);
        console.log("  From 18-decimal:", shares18);
        console.log("  From 24-decimal:", shares24);

        // All should convert to the same 18-decimal amount: 1000 * 10^18
        uint256 expected = 1000 * 10 ** 18;

        assertEq(shares6, expected, "6-decimal conversion should scale up correctly");
        assertEq(shares8, expected, "8-decimal conversion should scale up correctly");
        assertEq(shares18, expected, "18-decimal conversion should remain unchanged");
        assertEq(shares24, expected, "24-decimal conversion should scale down correctly");

        console.log("SUCCESS: All conversions produce equivalent 18-decimal shares!");
    }

    /// @notice Test convertToAssets when totalSupply == 0
    /// @dev Verifies proper decimal scaling from 18-decimal shares to asset decimals
    function testConvertToAssets_ZeroSupply_DecimalHandling() public view {
        console.log("\n=== convertToAssets Test - Zero Supply ===");

        // Test with equivalent share amounts: 1000 shares (in 18 decimals)
        uint256 shareAmount = 1000 * 10 ** 18;

        // Convert to assets (should result in amounts in each token's native decimals)
        uint256 assets6 = _tokenized(address(mechanism6)).convertToAssets(shareAmount);
        uint256 assets8 = _tokenized(address(mechanism8)).convertToAssets(shareAmount);
        uint256 assets18 = _tokenized(address(mechanism18)).convertToAssets(shareAmount);
        uint256 assets24 = _tokenized(address(mechanism24)).convertToAssets(shareAmount);

        console.log("Share amount (18 decimals):", shareAmount);

        console.log("\nConverted to assets (native decimals):");
        console.log("  To 6-decimal:", assets6);
        console.log("  To 8-decimal:", assets8);
        console.log("  To 18-decimal:", assets18);
        console.log("  To 24-decimal:", assets24);

        // Expected amounts in each token's native decimals
        uint256 expected6 = 1000 * 10 ** 6; // 1000 USDC
        uint256 expected8 = 1000 * 10 ** 8; // 1000 WBTC
        uint256 expected18 = 1000 * 10 ** 18; // 1000 ETH
        uint256 expected24 = 1000 * 10 ** 24; // 1000 HighPrec

        assertEq(assets6, expected6, "6-decimal conversion should scale down correctly");
        assertEq(assets8, expected8, "8-decimal conversion should scale down correctly");
        assertEq(assets18, expected18, "18-decimal conversion should remain unchanged");
        assertEq(assets24, expected24, "24-decimal conversion should scale up correctly");

        console.log("SUCCESS: All conversions produce correct native decimal amounts!");
    }

    /// @notice Test round-trip conversion consistency
    /// @dev Verifies that convertToShares -> convertToAssets returns original amount
    function testRoundTripConversion_ZeroSupply() public view {
        console.log("\n=== Round-trip Conversion Test ===");

        // Test various amounts for each token type
        uint256[] memory testAmounts6 = new uint256[](3);
        testAmounts6[0] = 1 * 10 ** 6; // 1 USDC
        testAmounts6[1] = 1000 * 10 ** 6; // 1000 USDC
        testAmounts6[2] = 1234567; // 1.234567 USDC

        uint256[] memory testAmounts18 = new uint256[](3);
        testAmounts18[0] = 1 * 10 ** 18; // 1 ETH
        testAmounts18[1] = 1000 * 10 ** 18; // 1000 ETH
        testAmounts18[2] = 123456789012345678; // 0.123... ETH

        console.log("Testing round-trip conversions...");

        // Test 6-decimal token round-trips
        for (uint i = 0; i < testAmounts6.length; i++) {
            uint256 originalAssets = testAmounts6[i];
            uint256 shares = _tokenized(address(mechanism6)).convertToShares(originalAssets);
            uint256 backToAssets = _tokenized(address(mechanism6)).convertToAssets(shares);

            console.log("6-decimal round-trip", i, "original:", originalAssets);
            console.log("  shares:", shares, "back to assets:", backToAssets);
            assertEq(backToAssets, originalAssets, "6-decimal round-trip should preserve original amount");
        }

        // Test 18-decimal token round-trips
        for (uint i = 0; i < testAmounts18.length; i++) {
            uint256 originalAssets = testAmounts18[i];
            uint256 shares = _tokenized(address(mechanism18)).convertToShares(originalAssets);
            uint256 backToAssets = _tokenized(address(mechanism18)).convertToAssets(shares);

            console.log("18-decimal round-trip", i, "original:", originalAssets);
            console.log("  shares:", shares, "back to assets:", backToAssets);
            assertEq(backToAssets, originalAssets, "18-decimal round-trip should preserve original amount");
        }

        console.log("SUCCESS: All round-trip conversions preserve original amounts!");
    }

    /// @notice Test edge case with very small amounts and decimal precision
    function testConversion_EdgeCases() public view {
        console.log("\n=== Edge Cases Test ===");

        // Test 1 wei/smallest unit for each token
        uint256 minAmount6 = 1; // 1 micro-USDC
        uint256 minAmount18 = 1; // 1 wei

        uint256 shares6 = _tokenized(address(mechanism6)).convertToShares(minAmount6);
        uint256 shares18 = _tokenized(address(mechanism18)).convertToShares(minAmount18);

        console.log("Minimum amounts:");
        console.log("  1 micro-USDC -> shares:", shares6);
        console.log("  1 wei -> shares:", shares18);

        // For 6-decimal token: 1 micro-USDC = 1 * 10^12 shares (scaled up 12 decimals)
        assertEq(shares6, 10 ** 12, "1 micro-USDC should convert to 10^12 shares");

        // For 18-decimal token: 1 wei = 1 share (no scaling)
        assertEq(shares18, 1, "1 wei should convert to 1 share");

        // Test back conversion
        uint256 backToAssets6 = _tokenized(address(mechanism6)).convertToAssets(shares6);
        uint256 backToAssets18 = _tokenized(address(mechanism18)).convertToAssets(shares18);

        assertEq(backToAssets6, minAmount6, "Round-trip should preserve 1 micro-USDC");
        assertEq(backToAssets18, minAmount18, "Round-trip should preserve 1 wei");

        console.log("SUCCESS: Edge cases handled correctly!");
    }
}
