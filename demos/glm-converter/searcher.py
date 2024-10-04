#!/usr/bin/env python3

import time
from datetime import datetime
import logging

import click
from eth_utils.abi import function_abi_to_4byte_selector, collapse_if_tuple
from web3 import Web3
from web3.exceptions import ContractCustomError, ContractLogicError

logging.basicConfig(
    format="%(asctime)s %(levelname)-8s %(message)s",
    level=logging.INFO,
    datefmt="[%H:%M:%S]",
)

token_abi = [
    {
        "inputs": ["address"],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    }
]

conv_abi = [
    {"inputs": [], "type": "error", "name": "Converter__SoftwareError"},
    {"inputs": [], "type": "error", "name": "Converter__SpendingTooMuch"},
    {"inputs": [], "type": "error", "name": "Converter__WrongPrevrandao"},
    {"inputs": [], "type": "error", "name": "Converter__RandomnessAlreadyUsed"},
    {"inputs": [], "type": "error", "name": "Converter__RandomnessUnsafeSeed"},
    {
        "inputs": [],
        "name": "buy",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "type": "function",
        "name": "price",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "lastBought",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "lastSold",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "saleValueLow",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "saleValueHigh",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "spent",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "startingBlock",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "spendADay",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "test_rand",
        "inputs": [],
        "outputs": [{"name": "", "type": "bool", "internalType": "bool"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "test_limit",
        "inputs": [],
        "outputs": [{"name": "", "type": "bool", "internalType": "bool"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "randao",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "chance",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view",
    },
]


def decode_custom_error(w3, contract_abi, error_data):
    for error in [abi for abi in contract_abi if abi["type"] == "error"]:
        # Get error signature components
        name = error["name"]
        data_types = [
            collapse_if_tuple(abi_input) for abi_input in error.get("inputs", [])
        ]
        error_signature_hex = function_abi_to_4byte_selector(error).hex()
        # Find match signature from error_data
        if error_signature_hex.casefold() == str(error_data.data)[2:10].casefold():
            params = ",".join(
                [
                    str(x)
                    for x in w3.codec.decode(
                        data_types, bytes.fromhex(str(error_data.data)[10:])
                    )
                ]
            )
            decoded = "%s(%s)" % (name, str(params))
            return decoded
    return None


def loop(converter, w3, state):
    # check if new block was mined
    block = w3.eth.get_block("latest")
    current_height = block["number"]
    if current_height == state["height"]:
        time.sleep(0.5)
        return
    state["height"] = current_height

    can_buy = False
    failure_reason = None
    try:
        converter.functions.buy().call()
        can_buy = True
    except ContractCustomError as exp:
        failure_reason = decode_custom_error(w3, conv_abi, exp)
        pass
    except ContractLogicError as exp:
        failure_reason = str(exp)
        pass
    except:
        failure_reason = "generic"
        pass

    if not can_buy:
        return failure_reason

    try:
        tx_hash = converter.functions.buy().transact()
        w3.eth.get_transaction_receipt(tx_hash)
    except ContractCustomError as exp:
        failure_reason = decode_custom_error(w3, conv_abi, exp)
        print(
            f"failed in transact() while being succesful in call() with error: {failure_reason}"
        )
        exit(1)
    except ContractLogicError as exp:
        print(f"Logic: {exp}")
        pass
    except BaseException as exp:
        pass


def get_spending_stats(block, converter, w3) -> (int, int):
    high = converter.functions.saleValueHigh().call()
    blocksADay = 7200
    spendADay = converter.functions.spendADay().call()
    startingBlock = converter.functions.startingBlock().call()
    height = block.number - startingBlock
    spent = converter.functions.spent().call()
    spendable = (height * (spendADay / blocksADay)) - spent
    return (int(high), int(spendable))


def get_price(converter):
    lastSold = float(converter.functions.lastSold().call() / 10**18)
    lastBought = float(converter.functions.lastBought().call() / 10**18)
    oraclePrice = 0.0
    try:
        oraclePrice = float(converter.functions.price().call() / 10**18)
    except ContractLogicError:
        pass
    return (oraclePrice, lastBought, lastSold)


@click.command
@click.option(
    "-v",
    "--verbose",
    is_flag=True,
    default=False,
    help="Print details.",
)
@click.option(
    "-pk",
    "--private-key",
    help="Key for account to pay for gas",
)
@click.option("-url", help="Ethereum ERC URL")
@click.option("-c", "--converter", help="Converter address")
def run(verbose, private_key, url, converter):
    w3 = Web3(Web3.HTTPProvider(url))
    assert w3.is_connected()

    converter = w3.eth.contract(address=converter, abi=conv_abi)

    state = {"height": 0}
    while True:
        prev = state["height"]
        reason = loop(converter, w3, state)
        cur = state["height"]
        if prev != cur:
            block = w3.eth.get_block("latest")
            (avg, spendable) = get_spending_stats(block, converter, w3)
            (oraclePrice, lastBought, lastSold) = get_price(converter)
            print(f"block {cur}; spendable: {float(spendable / avg):5.2f}; ", end="")
            print(f"oracle $GLM={oraclePrice:8.2f}; ", end="")
            if lastSold != 0:
                print(
                    f"actual $GLM={(lastBought/lastSold):.2f} = {lastBought:.2f} / {lastSold:.2f}; ",
                    end="",
                )
            print(f"{reason}")


if __name__ == "__main__":
    run()
