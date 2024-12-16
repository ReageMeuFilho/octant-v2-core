// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AddressRegistry is Ownable {
    mapping(bytes32 => address) private _addresses;

    event AddressSet(bytes32 id, address indexed newAddress);

    constructor(address _owner) Ownable(_owner) {}

    /**
     * @dev Sets an address for an id replacing the address saved in the addresses map
     * IMPORTANT Use this function carefully, as it will do a hard replacement
     * @param id The id
     * @param newAddress The address to set
     */
    function setAddress(bytes32 id, address newAddress) external onlyOwner {
        require(newAddress != address(0), "!zero");
        require(newAddress != _addresses[id], "!same");
        _addresses[id] = newAddress;
        emit AddressSet(id, newAddress);
    }

    /**
     * @dev Returns an address by id
     * @return The address
     */
    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }
}
