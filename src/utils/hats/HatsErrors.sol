// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

error Hats__InvalidAddressFor(string message, address a);
error Hats__InvalidHat(uint256 hatId);
error Hats__DoesNotHaveThisHat(address sender, uint256 hatId);
error Hats__HatAlreadyExists(bytes32 roleId);
error Hats__HatDoesNotExist(bytes32 roleId);
error Hats__NotAdminOfHat(address sender, uint256 hatId);
error Hats__TooManyInitialHolders(uint256 initialHolders, uint256 maxSupply);
