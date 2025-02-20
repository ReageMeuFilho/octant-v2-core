// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { NonfungibleDepositManager } from "src/dragons/eth2StakeVault/NonfungibleDepositManager.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";

/// @notice Harness contract that extends NonfungibleDepositManager to override tokenURI.
/// All token URI, JSON metadata, and on-chain SVG generation code has been moved here.
contract Eth2StakeVaultHarness is NonfungibleDepositManager {
    using Strings for uint256;

    // --- Data structure for constructing token URI ---
    struct ConstructTokenURIParams {
        uint256 tokenId;
        string withdrawalAddress;
        string withdrawalCredentials;
        string pubkey;
        string signature;
        string depositDataRoot;
        string status;
        uint8 progress; // progress level (0-4)
        bool pubkeySet;
        bool signatureSet;
        bool depositDataRootSet;
    }

    /**
     * @notice Generates dynamic NFT metadata including an on-chain SVG image for a given token ID
     * @dev Overrides ERC721.tokenURI to provide rich token metadata
     * @param tokenId The ID of the token to generate metadata for
     * @return string The base64 encoded JSON metadata string containing SVG image and token details
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        DepositInfo memory info = deposits[tokenId];

        // Derive dynamic text values from deposit info.
        string memory withdrawalAddr = toHexString(info.withdrawalAddress);
        string memory withdrawalCred = toHexString(info.withdrawalCredentials);
        string memory pubkeyStr = info.pubkey.length > 0 ? shortenHex(toHexString(info.pubkey)) : "";
        string memory signatureStr = info.signature.length > 0 ? shortenHex(toHexString(info.signature)) : "";
        string memory depositDataRootStr = info.depositDataRoot != 0
            ? shortenHex(toHexString(info.depositDataRoot))
            : "";
        string memory status = _stateToString(info.state);

        // Determine progress level: Requested=1, Assigned=2, Confirmed=3, Finalized=4, Cancelled=0.
        uint8 progress = 0;
        if (info.state == DepositState.Requested) progress = 1;
        else if (info.state == DepositState.Assigned) progress = 2;
        else if (info.state == DepositState.Confirmed) progress = 3;
        else if (info.state == DepositState.Finalized) progress = 4;
        else progress = 0;

        ConstructTokenURIParams memory params = ConstructTokenURIParams({
            tokenId: tokenId,
            withdrawalAddress: withdrawalAddr,
            withdrawalCredentials: withdrawalCred,
            pubkey: pubkeyStr,
            signature: signatureStr,
            depositDataRoot: depositDataRootStr,
            status: status,
            progress: progress,
            pubkeySet: info.pubkey.length > 0,
            signatureSet: info.signature.length > 0,
            depositDataRootSet: info.depositDataRoot != 0
        });

        return constructTokenURI(params);
    }

    /**
     * @notice Builds the complete token URI with metadata and SVG visualization
     * @dev Generates a base64 encoded JSON string containing token metadata and SVG image
     * @param params Struct containing all necessary parameters for URI construction
     * @return string The base64 encoded JSON metadata string
     */
    function constructTokenURI(ConstructTokenURIParams memory params) public pure returns (string memory) {
        string memory circles = _generateProgressCircles(params.progress);
        string memory checkmarksSVG = _generateCheckmarks(params);
        string memory svg = _generateSVG(params, circles, checkmarksSVG);

        return _wrapInBase64JSON(params.tokenId, params.status, svg);
    }

    /// @notice Generates the progress circles SVG component
    /// @param progress Current progress level (0-4)
    function _generateProgressCircles(uint8 progress) internal pure returns (string memory) {
        string memory circles = "";
        for (uint8 i = 0; i < 4; i++) {
            string memory fillColor = i < progress ? "#48BB78" : "#4A5568";
            string memory r = "4";
            if (i == progress - 1 && progress > 0) {
                r = "6";
            }
            circles = string(
                abi.encodePacked(
                    circles,
                    '<circle cx="',
                    uint256(i * 16).toString(),
                    '" cy="14" r="',
                    r,
                    '" fill="',
                    fillColor,
                    '"/>'
                )
            );
        }
        return string(abi.encodePacked('<g transform="translate(320,50)">', circles, "</g>"));
    }

    /// @notice Generates the checkmarks SVG component
    function _generateCheckmarks(ConstructTokenURIParams memory params) internal pure returns (string memory) {
        string[6] memory checkmarks;
        checkmarks[0] = '<path d="M360 138 l4 4 l8 -8" stroke="#48BB78" stroke-width="2" fill="none"/>';
        checkmarks[1] = '<path d="M360 188 l4 4 l8 -8" stroke="#48BB78" stroke-width="2" fill="none"/>';
        if (params.pubkeySet) {
            checkmarks[2] = '<path d="M360 238 l4 4 l8 -8" stroke="#48BB78" stroke-width="2" fill="none"/>';
        }
        if (params.signatureSet) {
            checkmarks[3] = '<path d="M360 288 l4 4 l8 -8" stroke="#48BB78" stroke-width="2" fill="none"/>';
        }
        if (params.depositDataRootSet) {
            checkmarks[4] = '<path d="M360 338 l4 4 l8 -8" stroke="#48BB78" stroke-width="2" fill="none"/>';
        }
        if (bytes(params.status).length > 0) {
            checkmarks[5] = '<path d="M360 388 l4 4 l8 -8" stroke="#48BB78" stroke-width="2" fill="none"/>';
        }
        return
            string(
                abi.encodePacked(
                    '<g fill="#48BB78">',
                    checkmarks[0],
                    checkmarks[1],
                    checkmarks[2],
                    checkmarks[3],
                    checkmarks[4],
                    checkmarks[5],
                    "</g>"
                )
            );
    }

    /// @notice Generates the main SVG content
    function _generateSVG(
        ConstructTokenURIParams memory params,
        string memory circles,
        string memory checkmarksSVG
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    _generateSVGHeader(),
                    _generateSVGBackground(),
                    _generateTextElements(params),
                    circles,
                    checkmarksSVG,
                    "</svg>"
                )
            );
    }

    /// @notice Generates the SVG header and container
    function _generateSVGHeader() internal pure returns (string memory) {
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 460">';
    }

    /// @notice Generates the SVG background elements
    function _generateSVGBackground() internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<rect width="400" height="460" rx="12" fill="#2E2E2E" stroke="#F6E05E" stroke-width="2"/>',
                    '<path d="M12 2 h376 a10,10 0 0 1 10,10 v87 h-396 v-87 a10,10 0 0 1 10,-10" fill="#1A1A1A"/>',
                    '<path d="M100 160l-30-15 30-50 30 50-30 15zm0 10l-30-15 30 15 30-15-30 15z" fill="#4A5568" fill-opacity="0.2"/>',
                    '<path d="M300 400l-20 10v-20l20-30 20 30v20l-20-10z" fill="#4A5568" fill-opacity="0.2"/>'
                )
            );
    }

    /// @notice Generates the text elements for the SVG
    function _generateTextElements(ConstructTokenURIParams memory params) internal pure returns (string memory) {
        return string(abi.encodePacked(_generateLabels(), _generateValues(params)));
    }

    /// @notice Generates the label text elements
    function _generateLabels() internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<text x="24" y="44" font-family="system-ui, sans-serif" font-size="22" font-weight="700" fill="white" letter-spacing="0.5">Validator Deposit</text>',
                    '<text x="24" y="70" font-family="system-ui, sans-serif" font-size="16" fill="#A0AEC0">ETH 2.0 Staking</text>',
                    '<text x="24" y="130" font-family="monospace" font-size="12" fill="#718096">Withdrawal Address</text>',
                    '<text x="24" y="180" font-family="monospace" font-size="12" fill="#718096">Withdrawal Credentials</text>',
                    '<text x="24" y="230" font-family="monospace" font-size="12" fill="#718096">Public Key</text>',
                    '<text x="24" y="280" font-family="monospace" font-size="12" fill="#718096">Signature</text>',
                    '<text x="24" y="330" font-family="monospace" font-size="12" fill="#718096">Deposit Data Root</text>',
                    '<text x="24" y="380" font-family="monospace" font-size="12" fill="#718096">Status</text>'
                )
            );
    }

    /// @notice Generates the value text elements
    function _generateValues(ConstructTokenURIParams memory params) internal pure returns (string memory) {
        // Get display values with fallbacks
        string memory withdrawalAddrText = bytes(params.withdrawalAddress).length > 0 ? params.withdrawalAddress : "-";
        string memory withdrawalCredText = bytes(params.withdrawalCredentials).length > 0
            ? params.withdrawalCredentials
            : "-";
        string memory pubkeyText = bytes(params.pubkey).length > 0 ? params.pubkey : "-";
        string memory signatureText = bytes(params.signature).length > 0 ? params.signature : "-";
        string memory depositDataRootText = bytes(params.depositDataRoot).length > 0 ? params.depositDataRoot : "-";

        return
            string(
                abi.encodePacked(
                    _generateValuesPart1(withdrawalAddrText, withdrawalCredText, pubkeyText),
                    _generateValuesPart2(signatureText, depositDataRootText, params.status)
                )
            );
    }

    /// @notice Generates the first part of value text elements
    function _generateValuesPart1(
        string memory withdrawalAddrText,
        string memory withdrawalCredText,
        string memory pubkeyText
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<text x="24" y="150" font-family="monospace" font-size="14" fill="#E2E8F0">',
                    withdrawalAddrText,
                    "</text>",
                    '<text x="24" y="200" font-family="monospace" font-size="14" fill="#E2E8F0">',
                    withdrawalCredText,
                    "</text>",
                    '<text x="24" y="250" font-family="monospace" font-size="14" fill="#E2E8F0">',
                    pubkeyText,
                    "</text>"
                )
            );
    }

    /// @notice Generates the second part of value text elements
    function _generateValuesPart2(
        string memory signatureText,
        string memory depositDataRootText,
        string memory status
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<text x="24" y="300" font-family="monospace" font-size="14" fill="#E2E8F0">',
                    signatureText,
                    "</text>",
                    '<text x="24" y="350" font-family="monospace" font-size="14" fill="#E2E8F0">',
                    depositDataRootText,
                    "</text>",
                    '<text x="24" y="400" font-family="monospace" font-size="14" fill="#E2E8F0">',
                    status,
                    "</text>"
                )
            );
    }

    /// @notice Wraps the SVG in base64 encoded JSON
    function _wrapInBase64JSON(
        uint256 tokenId,
        string memory status,
        string memory svg
    ) internal pure returns (string memory) {
        string memory json = string(
            abi.encodePacked(
                '{"name": "Validator Deposit #',
                tokenId.toString(),
                '", "description": "A Validator Deposit NFT representing a 32 ETH deposit. Current state: ',
                status,
                '", "image": "data:image/svg+xml;base64,',
                Base64.encode(bytes(svg)),
                '"}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // --- Utility Functions for Hex Conversions ---

    /**
     * @notice Converts an Ethereum address to its checksummed hex string representation
     * @dev Utilizes OpenZeppelin's Strings library for hex conversion
     * @param account The address to convert
     * @return string The hex string representation of the address
     */
    function toHexString(address account) internal pure returns (string memory) {
        return Strings.toHexString(uint160(account), 20);
    }

    /**
     * @notice Converts a bytes32 value to its hex string representation
     * @param data The bytes32 value to convert
     * @return string The hex string representation of the bytes32 value
     */
    function toHexString(bytes32 data) internal pure returns (string memory) {
        return Strings.toHexString(uint256(data), 32);
    }

    /**
     * @notice Converts arbitrary bytes to a hex string representation
     * @dev Decodes bytes to uint256 before conversion
     * @param data The bytes array to convert
     * @return string The hex string representation of the bytes
     */
    function toHexString(bytes memory data) internal pure returns (string memory) {
        uint256 length = data.length;
        return Strings.toHexString(uint256(abi.decode(data, (uint256))), length);
    }

    /**
     * @notice Creates a shortened version of a hex string for display purposes
     * @dev Shows first 6 and last 4 characters with "..." in between
     * @param hexStr The hex string to shorten
     * @return string The shortened hex string or original if length <= 10
     */
    function shortenHex(string memory hexStr) internal pure returns (string memory) {
        bytes memory b = bytes(hexStr);
        if (b.length <= 10) return hexStr;
        bytes memory short = new bytes(13);
        for (uint256 i = 0; i < 6; i++) {
            short[i] = b[i];
        }
        short[6] = bytes1(uint8(46)); // '.'
        short[7] = bytes1(uint8(46));
        short[8] = bytes1(uint8(46));
        for (uint256 i = 0; i < 4; i++) {
            short[9 + i] = b[b.length - 4 + i];
        }
        return string(short);
    }

    /**
     * @notice Converts a DepositState enum value to its string representation
     * @dev Maps each enum value to a human-readable string
     * @param state The DepositState enum value to convert
     * @return string The string representation of the deposit state
     */
    function _stateToString(DepositState state) internal pure returns (string memory) {
        if (state == DepositState.Requested) return "Requested";
        if (state == DepositState.Assigned) return "Assigned";
        if (state == DepositState.Confirmed) return "Confirmed";
        if (state == DepositState.Finalized) return "Finalized";
        if (state == DepositState.Cancelled) return "Cancelled";
        return "Unknown";
    }
}
