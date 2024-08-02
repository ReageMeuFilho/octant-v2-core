/* SPDX-License-Identifier: GPL-3.0 */

pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {

    struct NetworkConfig {
        address glmToken;
        address wethToken;
        address nonfungiblePositionManager;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            glmToken: 0x71432DD1ae7DB41706ee6a22148446087BdD0906,
            wethToken: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            nonfungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory) {
        if (activeNetworkConfig.glmToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        ERC20Mock wethMock = new ERC20Mock();
        ERC20Mock glmMock = new ERC20Mock();

        vm.stopBroadcast();

        return NetworkConfig({
            glmToken: address(glmMock),
            wethToken: address(wethMock),
            nonfungiblePositionManager: address(0), // deploy
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}