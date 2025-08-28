// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { DragonBaseStrategy, ERC20 } from "src/zodiac-core/vaults/DragonBaseStrategy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IStrategy } from "src/zodiac-core/interfaces/IStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626Payable } from "src/zodiac-core/interfaces/IERC4626Payable.sol";

contract YearnPolygonUsdcStrategy is DragonBaseStrategy {
    /// @dev Yearn Polygon Aave V3 USDC Lender Vault
    address public constant YIELD_SOURCE = 0x52367C8E381EDFb068E9fBa1e7E9B2C847042897;

    /// @dev Initialize function, will be triggered when a new proxy is deployed
    /// @dev owner of this module will the safe multisig that calls setUp function
    /// @param initializeParams Parameters of initialization encoded
    function setUp(bytes memory initializeParams) public override initializer {
        /// @dev Strategy specific parameters
        /// @dev USDC Polygon
        address _asset = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

        (address _owner, bytes memory data) = abi.decode(initializeParams, (address, bytes));

        (
            address _tokenizedStrategyImplementation,
            address _management,
            address _keeper,
            address _dragonRouter,
            uint256 _maxReportDelay,
            address _regenGovernance
        ) = abi.decode(data, (address, address, address, address, uint256, address));
        // Effects
        __Ownable_init(msg.sender);
        string memory _name = "Octant Polygon USDC Strategy";
        setAvatar(_owner);
        setTarget(_owner);
        transferOwnership(_owner);

        // Interactions
        __BaseStrategy_init(
            _tokenizedStrategyImplementation,
            _asset,
            _owner,
            _management,
            _keeper,
            _dragonRouter,
            _maxReportDelay,
            _name,
            _regenGovernance
        );

        ERC20(_asset).approve(YIELD_SOURCE, type(uint256).max);
        IERC20(YIELD_SOURCE).approve(_owner, type(uint256).max);
    }

    function availableDepositLimit(address _user) public view override returns (uint256) {
        uint256 actualLimit = super.availableDepositLimit(_user);
        uint256 vaultLimit = IStrategy(YIELD_SOURCE).availableDepositLimit(address(this));
        return Math.min(actualLimit, vaultLimit);
    }

    function _deployFunds(uint256 _amount) internal override {
        uint256 limit = IStrategy(YIELD_SOURCE).availableDepositLimit(address(this));
        _amount = Math.min(_amount, limit);
        if (_amount > 0) {
            IERC4626Payable(YIELD_SOURCE).deposit(_amount, address(this));
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 _withdrawAmount = Math.min(_amount, IERC4626Payable(YIELD_SOURCE).maxWithdraw(address(this)));
        IERC4626Payable(YIELD_SOURCE).withdraw(_withdrawAmount, address(this), address(this));
    }

    /* @dev As we are using yearn vault, the strategy accrues yield in the vault. so the value of strategy's shares
     * is increased therefore to accrue rewards to the dragon router we have to withdraw all funds and deposit back the remaining funds after
     * shares of dragon router are allocated.
     */
    function _harvestAndReport() internal override returns (uint256) {
        uint256 _withdrawAmount = IERC4626Payable(YIELD_SOURCE).maxWithdraw(address(this));
        IERC4626Payable(YIELD_SOURCE).withdraw(_withdrawAmount, address(this), address(this));
        return ERC20(asset).balanceOf(address(this));
    }

    function _tend(uint256 /*_idle*/) internal override {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        if (balance > 0) {
            IERC4626Payable(YIELD_SOURCE).deposit(balance, address(this));
        }
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        IERC4626Payable(YIELD_SOURCE).withdraw(_amount, address(this), address(this));
    }

    function _tendTrigger() internal pure override returns (bool) {
        return true;
    }
}
