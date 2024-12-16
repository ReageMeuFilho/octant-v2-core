// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.23;

interface IAddressRegistry {
    function getAddress(bytes32 id) external view returns (address);
}
