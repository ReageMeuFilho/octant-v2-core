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
        address uniswapV3Router;
        address uniswapGlmWeth10000Pool;
    }

    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 1) {
            // running on mainnet or on a mainnet fork
            activeNetworkConfig = getMainnetEthConfig();
        }
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                glmToken: 0x71432DD1ae7DB41706ee6a22148446087BdD0906,
                wethToken: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
                nonfungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
                uniswapV3Router: 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD,
                uniswapGlmWeth10000Pool: 0x8C315b47CC6c25aF900C73E0689C106b50D5c6DF,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getMainnetEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                glmToken: 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429,
                wethToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                nonfungiblePositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
                uniswapV3Router: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                uniswapGlmWeth10000Pool: 0x531b6A4b3F962208EA8Ed5268C642c84BB29be0b,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.glmToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        ERC20Mock wethMock = new ERC20Mock();
        ERC20Mock glmMock = new ERC20Mock();

        vm.stopBroadcast();

        return
            NetworkConfig({
                glmToken: address(glmMock),
                wethToken: address(wethMock),
                nonfungiblePositionManager: address(0), // deploy
                uniswapV3Router: address(0),
                uniswapGlmWeth10000Pool: address(0),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
