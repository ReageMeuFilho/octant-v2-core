// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {Hats} from "lib/hats-protocol/src/Hats.sol";

contract DeployHats is Test {
    /// @notice The Hats contract instance
    Hats public hats;
    bytes32 public salt;

    string constant baseImageURI = "ipfs://bafkreiflezpk3kjz6zsv23pbvowtatnd5hmqfkdro33x5mh2azlhne3ah4";
    string public constant name = "Hats Protocol";

    function deploy() public virtual {
        deployWithSalt(generateRandomBytes32());
    }

    function deployWithSalt(bytes32 _salt) public virtual {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        hats = new Hats{salt: _salt}(name, baseImageURI);
        salt = _salt;

        vm.stopBroadcast();
    }

    function generateRandomBytes32() public view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender));
    }
}
