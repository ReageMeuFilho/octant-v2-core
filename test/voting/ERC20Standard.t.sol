// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity >=0.8.25;

// import {Setup} from "./Setup.sol";
// import {VaultSharesNotTransferable} from "src/errors.sol";

// contract ERC20BaseTest is Setup {
//     address internal immutable self = address(this);
//     bytes internal constant ARITHMETIC_ERROR = abi.encodeWithSignature("Panic(uint256)", 0x11);

//     function setUp() public override {
//         super.setUp();
//     }

//     function test_metadata() public view {
//         assertEq(strategy.name(), "Test Impact Strategy");
//         assertEq(strategy.symbol(), string(abi.encodePacked("imp", asset.symbol())));
//         assertEq(strategy.decimals(), 18);
//         assertEq(strategy.apiVersion(), "1.0.0");
//     }

//     function testFuzz_deposit(uint256 amount_) public {
//         amount_ = bound(amount_, minFuzzAmount, maxFuzzAmount);
        
//         // Mint and deposit
//         asset.mint(alice, amount_);
//         vm.prank(alice);
//         asset.approve(address(strategy), amount_);
        
//         vm.prank(alice);
//         strategy.deposit(amount_, alice);

//         assertEq(strategy.balanceOf(alice), amount_);
//         assertEq(strategy.totalSupply(), amount_);
//         assertEq(strategy.totalAssets(), amount_);
//     }

//     function testFuzz_approve(uint256 amount_) public {
//         amount_ = bound(amount_, minFuzzAmount, maxFuzzAmount);

//         assertTrue(strategy.approve(alice, amount_));
//         assertEq(strategy.allowance(self, alice), amount_);
//     }

//     function test_transfer_reverts() public {
//         uint256 amount_ = 1000e18;
//         address recipient_ = address(0x123);

//         // Initial deposit
//         depositAndVote(alice, amount_, project1);

//         // Attempt transfer
//         vm.prank(alice);
//         vm.expectRevert(abi.encodeWithSelector(VaultSharesNotTransferable.selector));
//         strategy.transfer(recipient_, amount_);

//         assertEq(strategy.balanceOf(recipient_), 0);
//         assertEq(strategy.balanceOf(alice), amount_);
//     }

//     function test_transferFrom_reverts() public {
//         uint256 amount_ = 1000e18;
//         address recipient_ = address(0x123);

//         // Initial deposit
//         depositAndVote(alice, amount_, project1);

//         // Approve transfer
//         vm.prank(alice);
//         strategy.approve(self, amount_);

//         // Attempt transferFrom
//         vm.expectRevert(abi.encodeWithSelector(VaultSharesNotTransferable.selector));
//         strategy.transferFrom(alice, recipient_, amount_);

//         assertEq(strategy.balanceOf(recipient_), 0);
//         assertEq(strategy.balanceOf(alice), amount_);
//     }
// }

// contract ERC20PermitTest is Setup {
//     uint256 internal constant S_VALUE_INCLUSIVE_UPPER_BOUND =
//         uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0);
//     uint256 internal constant WAD = 10 ** 18;

//     address internal _owner;
//     address internal _spender;
//     uint256 internal _skOwner = 1;
//     uint256 internal _skSpender = 2;
//     uint256 internal _nonce = 0;
//     uint256 internal _deadline = 5_000_000_000;

//     ERC20User internal _user;

//     function setUp() public override {
//         super.setUp();
//         _owner = vm.addr(_skOwner);
//         _spender = vm.addr(_skSpender);
//         vm.warp(_deadline - 52 weeks);
//         _user = new ERC20User();
//     }
// } 