// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockStrategy.sol";
import "./MockIntentProtocol.sol";
import "./MockESF.sol";
import "forge-std/console.sol";

contract MockDragonRouter {
    using SafeERC20 for IERC20;

    struct Recipient {
        uint256 bps;
        address desiredToken;
        uint256 shares;
        uint256 redeemedShares;
    }

    MockStrategy public strategy;
    MockIntentProtocol public intentProtocol;
    mapping(address => Recipient) public recipients;
    address[] public recipientList;
    uint256 public totalBps;
    mapping(address => uint256) public totalReportedShares;
    bytes4 private constant MAGIC_VALUE = 0x1626ba7e;

    constructor(address _strategy, address _intentProtocol) {
        strategy = MockStrategy(_strategy);
        intentProtocol = MockIntentProtocol(_intentProtocol);
    }

    function addRecipient(address recipient, uint256 bps, address desiredToken) external {
        require(totalBps + bps <= 10000, "Total BPS exceeds 100%");
        recipients[recipient] = Recipient({ bps: bps, desiredToken: desiredToken, shares: 0, redeemedShares: 0 });
        recipientList.push(recipient);
        totalBps += bps;
    }

    function addNewShares(uint256 _newShares) external {
        totalReportedShares[msg.sender] += _newShares;
    }

    function report() external {
        strategy.report();
    }

    function withdrawAndConvert(
        address sharesOwner,
        uint256 deadline,
        uint256 minOut,
        bytes memory signature
    ) external returns (bytes32) {
        Recipient storage recipient = recipients[sharesOwner];
        require(recipient.bps > 0, "Not a recipient");

        // Verify operator signature if sharesOwner is an ESF
        if (sharesOwner.code.length > 0 && sharesOwner != msg.sender) {
            bytes32 hash = keccak256(abi.encodePacked(deadline, minOut));
            require(
                IERC1271(sharesOwner).isValidSignature(hash, signature) == MAGIC_VALUE,
                "Invalid operator signature"
            );
        }

        uint256 recipientRedeemedShares = recipient.redeemedShares;

        // if recipientRedeemedShares is < to what is expected based on totalReportedShares and bps, set it as unprocessedShares
        uint256 unprocessedShares = (totalReportedShares[address(strategy)] * recipient.bps) /
            10000 -
            recipientRedeemedShares;

        require(unprocessedShares > 0, "No new shares to claim");

        recipient.redeemedShares += unprocessedShares;

        uint256 underlyingAmount = strategy.unwrap(unprocessedShares);
        IERC20(strategy.asset()).approve(address(intentProtocol), underlyingAmount);

        return
            intentProtocol.createIntent(
                strategy.asset(),
                recipient.desiredToken,
                underlyingAmount,
                minOut,
                deadline,
                sharesOwner,
                address(this)
            );
    }
}
