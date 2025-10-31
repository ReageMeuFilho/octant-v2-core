// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import { Trader } from "src/utils/routers-transformers/Trader.sol";
import { UniV3Swap } from "src/utils/vendor/0xSplits/UniV3Swap.sol";
import { HelperConfig } from "../helpers/HelperConfig.s.sol";
import { DeployTrader } from "../deploy/DeployTrader.sol";

contract DeployTraderHelper is DeployTrader {
    HelperConfig config = new HelperConfig(false);
    string buff = "";

    function run() external {
        (address glmToken, address wethToken, , uint256 deployerKey, , , , , address uniV3Swap, ) = config
            .activeNetworkConfig();
        wethAddress = wethToken;
        glmAddress = glmToken;
        address base;
        address quote;
        uint24 fee;
        string memory poolName;

        preprompt2("Chain id is: ", vm.toString(block.chainid));
        try vm.prompt(prompt("Input owner address")) returns (string memory res) {
            owner = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Deployment aborted");
        }
        try vm.prompt(prompt("Input beneficiary address")) returns (string memory res) {
            beneficiary = vm.parseAddress(res);
        } catch (bytes memory) {
            revert("Deployment aborted");
        }
        try vm.prompt(listPairsPrompt()) returns (string memory _poolName) {
            (base, quote, fee) = config.poolByName(_poolName);
            poolName = _poolName;
            require(base != address(0x0));
        } catch (bytes memory) {
            revert(string.concat("Unknown pair"));
        }
        preprompt2("Base: ", vm.toString(base));
        preprompt2("Quote: ", vm.toString(quote));
        preprompt2("Fee: ", vm.toString(fee));
        preprompt2(
            "V3 pool address: ",
            vm.toString(config.getPoolAddress(uniEthWrapper(base), uniEthWrapper(quote), fee))
        );
        initializer = UniV3Swap(payable(uniV3Swap));
        preprompt2("uniV3Swap at: ", vm.toString(address(initializer)));
        preprompt2("Beneficiary is: ", vm.toString(beneficiary));

        bool doDeploy = false;
        try vm.prompt(prompt("Continue (yes/no)?")) returns (string memory res) {
            if (keccak256(abi.encode(res)) == keccak256(abi.encode("yes"))) {
                doDeploy = true;
            }
        } catch (bytes memory) {
            revert("Deployment aborted");
        }
        if (!doDeploy) revert("Deployment aborted");

        vm.startBroadcast(deployerKey);
        configureTrader(config, poolName);
        vm.stopBroadcast();

        console.log("Trader deployed at: ", address(trader));
        console.log("Swapper deployed at: ", address(swapper));
        console.log("Ownership transferred to: ", owner);
    }

    function listPairsPrompt() public returns (string memory result) {
        preprompt1("Following pools are configured:");
        for (uint256 i; i < config.poolCount(); i++) {
            preprompt2("- ", config.pools(i));
        }
        return prompt("Please enter pool name which will be used to trade");
    }

    function prompt(string memory _str) public returns (string memory) {
        string memory summary = string.concat(buff, "\n");
        buff = "";
        return string.concat(summary, _str);
    }

    function preprompt1(string memory _str) public {
        buff = string.concat(buff, "\n");
        buff = string.concat(buff, _str);
    }

    function preprompt2(string memory _str1, string memory _str2) public {
        buff = string.concat(buff, "\n");
        buff = string.concat(buff, _str1);
        buff = string.concat(buff, _str2);
    }
}
