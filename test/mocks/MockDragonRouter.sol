// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.25;
import { IDragonRouter } from "src/interfaces/IDragonRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDragonRouter is IDragonRouter {
    using SafeERC20 for IERC20;
    address public metaPool;
    address public dragon;
    IERC20 public asset;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public shares;

    constructor(address token, address _pool, address _dragon) {
        metaPool = _pool;
        dragon = _dragon;
        asset = IERC20(token);
        balances[metaPool] = 0;
        balances[dragon] = 0;
        shares[metaPool] = 50;
        shares[dragon] = 50;
    }

    /**
     * @dev Distributes new splits to all shareholders.
     * @param amount The amount of tokens to distribute.
     */
    function fundFromSource(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);

        balances[metaPool] += amount / 2;
        balances[dragon] += amount / 2;
    }

    /**
     * @dev Mints new shares for a user.
     * @param to The address receiving the shares.
     * @param amount The number of shares to mint.
     */
    function mint(address to, uint256 amount) external {
        shares[to] += amount;
    }

    /**
     * @dev Burns shares from a user.
     * @param from The address to burn shares from.
     * @param amount The number of shares to burn.
     */
    function burn(address from, uint256 amount) external {
        shares[from] -= amount;
    }

    /**
     * @dev Allows a user to claim their available split, optionally transforming it.
     */
    function claimSplit() external {
        uint256 tempBalance = balances[msg.sender];
        balances[msg.sender] = 0;
        // send the balance to the user
        asset.safeTransfer(msg.sender, tempBalance);
    }
}
