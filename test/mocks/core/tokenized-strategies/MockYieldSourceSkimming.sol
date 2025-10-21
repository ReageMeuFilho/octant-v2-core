// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockYieldSourceSkimming is ERC4626 {
    uint256 public _pricePerShare;

    constructor(address _asset) ERC4626(IERC20(_asset)) ERC20("Mock Yield Source Skimming", "YSS") {}

    // mint shares
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function pricePerShare() public view returns (uint256) {
        if (_pricePerShare != 0) return _pricePerShare;
        uint256 _balance = ERC20(asset()).balanceOf(address(this));
        uint256 decimals = ERC20(asset()).decimals();

        return (_balance * 10 ** decimals) / totalSupply();
    }

    function simulateLoss(uint256 _amount) public {
        ERC20(asset()).transfer(msg.sender, _amount);
    }

    function setPricePerShare(uint256 _pricePerShareAmount) public {
        _pricePerShare = _pricePerShareAmount;
    }
}
