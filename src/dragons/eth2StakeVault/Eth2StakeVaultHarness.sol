// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Eth2StakeVault } from "src/dragons/eth2StakeVault/ETH2StakeVault.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";

/// @notice Harness contract that extends NonfungibleDepositManager to override tokenURI.
/// All token URI, JSON metadata, and on-chain SVG generation code has been moved here.
contract Eth2StakeVaultHarness is Eth2StakeVault {
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
     * @notice Override ERC721.tokenURI to generate dynamic metadata including an on-chain SVG image.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        DepositInfo memory info = deposits[tokenId];

        // Derive dynamic text values from deposit info.
        string memory withdrawalAddr = toHexString(info.withdrawalAddress);
        string memory withdrawalCred = toHexString(info.withdrawalCredentials);
        string memory pubkeyStr = info.pubkey.length > 0 ? shortenHex(toHexString(info.pubkey)) : "";
        string memory signatureStr = info.signature.length > 0 ? shortenHex(toHexString(info.signature)) : "";
        string memory depositDataRootStr = info.depositDataRoot != 0 ? shortenHex(toHexString(info.depositDataRoot)) : "";
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
     * @notice Constructs the token URI (base64 JSON metadata) including an on-chain SVG image.
     */
    function constructTokenURI(ConstructTokenURIParams memory params) public pure returns (string memory) {
        // Build progress circles: 4 circles. For each index 0 to 3, fill green if index < progress; else grey.
        string memory circles = "";
        for (uint8 i = 0; i < 4; i++) {
            string memory fillColor = i < params.progress ? "#48BB78" : "#4A5568";
            // For simplicity, using fixed positions and a constant radius (r).
            string memory r = "4";
            if (i == params.progress - 1 && params.progress > 0) {
                r = "6";
            }
            circles = string(abi.encodePacked(
                circles,
                '<circle cx="', (i * 16).toString(), '" cy="14" r="', r, '" fill="', fillColor, '"/>'
            ));
        }
        circles = string(abi.encodePacked('<g transform="translate(320,50)">', circles, "</g>"));

        // Build checkmarks for various fields (6 positions).
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
        string memory checkmarksSVG = string(
            abi.encodePacked(
                "<g fill=\"#48BB78\">",
                checkmarks[0],
                checkmarks[1],
                checkmarks[2],
                checkmarks[3],
                checkmarks[4],
                checkmarks[5],
                "</g>"
            )
        );

        // Fallback placeholders for missing values.
        string memory withdrawalAddrText = bytes(params.withdrawalAddress).length > 0 ? params.withdrawalAddress : "—";
        string memory withdrawalCredText = bytes(params.withdrawalCredentials).length > 0 ? params.withdrawalCredentials : "—";
        string memory pubkeyText = bytes(params.pubkey).length > 0 ? params.pubkey : "—";
        string memory signatureText = bytes(params.signature).length > 0 ? params.signature : "—";
        string memory depositDataRootText = bytes(params.depositDataRoot).length > 0 ? params.depositDataRoot : "—";

        // Construct the SVG image using the provided template.
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 460">',
                    // Card Background
                    '<rect width="400" height="460" rx="12" fill="#2E2E2E" stroke="#F6E05E" stroke-width="2"/>',
                    // Darker Header Section
                    '<path d="M12 2 h376 a10,10 0 0 1 10,10 v87 h-396 v-87 a10,10 0 0 1 10,-10" fill="#1A1A1A"/>',
                    // Ethereum Logo (top left)
                    '<path d="M100 160l-30-15 30-50 30 50-30 15zm0 10l-30-15 30 15 30-15-30 15z" fill="#4A5568" fill-opacity="0.2"/>',
                    // Validator Shield (bottom right)
                    '<path d="M300 400l-20 10v-20l20-30 20 30v20l-20-10z" fill="#4A5568" fill-opacity="0.2"/>',
                    // Title Text
                    '<text x="24" y="44" font-family="system-ui, sans-serif" font-size="22" font-weight="700" fill="white" letter-spacing="0.5">Validator Deposit</text>',
                    // Subtitle Text
                    '<text x="24" y="70" font-family="system-ui, sans-serif" font-size="16" fill="#A0AEC0">ETH 2.0 Staking</text>',
                    // Progress Circles
                    circles,
                    // Deposit Information Section - Labels
                    '<text x="24" y="130" font-family="monospace" font-size="12" fill="#718096">Withdrawal Address</text>',
                    '<text x="24" y="180" font-family="monospace" font-size="12" fill="#718096">Withdrawal Credentials</text>',
                    '<text x="24" y="230" font-family="monospace" font-size="12" fill="#718096">Public Key</text>',
                    '<text x="24" y="280" font-family="monospace" font-size="12" fill="#718096">Signature</text>',
                    '<text x="24" y="330" font-family="monospace" font-size="12" fill="#718096">Deposit Data Root</text>',
                    '<text x="24" y="380" font-family="monospace" font-size="12" fill="#718096">Status</text>',
                    // Deposit Information Section - Values
                    '<text x="24" y="150" font-family="monospace" font-size="14" fill="#E2E8F0">', withdrawalAddrText, '</text>',
                    '<text x="24" y="200" font-family="monospace" font-size="14" fill="#E2E8F0">', withdrawalCredText, '</text>',
                    '<text x="24" y="250" font-family="monospace" font-size="14" fill="#E2E8F0">', pubkeyText, '</text>',
                    '<text x="24" y="300" font-family="monospace" font-size="14" fill="#E2E8F0">', signatureText, '</text>',
                    '<text x="24" y="350" font-family="monospace" font-size="14" fill="#E2E8F0">', depositDataRootText, '</text>',
                    '<text x="24" y="400" font-family="monospace" font-size="14" fill="#E2E8F0">', params.status, '</text>',
                    // Checkmarks
                    checkmarksSVG,
                '</svg>'
            )
        );

        // Construct JSON metadata.
        string memory json = string(
            abi.encodePacked(
                '{"name": "Validator Deposit #', params.tokenId.toString(),
                '", "description": "A Validator Deposit NFT representing a 32 ETH deposit. Current state: ', params.status,
                '", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
                '"}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // --- Utility Functions for Hex Conversions ---

    /**
     * @dev Converts an address to its checksummed hex string.
     */
    function toHexString(address account) internal pure returns (string memory) {
        return Strings.toHexString(uint160(account), 20);
    }

    /**
     * @dev Converts bytes32 to hex string.
     */
    function toHexString(bytes32 data) internal pure returns (string memory) {
        return Strings.toHexString(uint256(data), 32);
    }

    /**
     * @dev Converts arbitrary bytes to hex string.
     */
    function toHexString(bytes memory data) internal pure returns (string memory) {
        uint256 length = data.length;
        return Strings.toHexString(uint256(abi.decode(data, (uint256))), length);
    }

    /**
     * @dev Shortens a hex string by showing the first 6 and last 4 characters, separated by "..."
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
     * @dev Converts a DepositState enum to a string.
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