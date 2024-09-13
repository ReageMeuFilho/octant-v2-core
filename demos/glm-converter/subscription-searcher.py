#!/usr/bin/env python3

import asyncio
import json
import os
import requests
from websockets import connect

from eth_utils.abi import function_abi_to_4byte_selector, collapse_if_tuple
from web3 import Web3
from web3.exceptions import ContractCustomError, ContractLogicError

import logging
logging.basicConfig(format='%(asctime)s %(message)s', level=logging.INFO)

conv_abi = [
    {
        "inputs": [],
        "type": "error",
        "name": "Converter__SoftwareError"
    },
    {
        "inputs": [],
        "type": "error",
        "name": "Converter__SpendingTooMuch"
    },
    {
        "inputs": [],
        "type": "error",
        "name": "Converter__WrongPrevrandao"
    },
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
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "lastBought",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "lastSold",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "saleValueLow",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "saleValueHigh",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "spent",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "startingBlock",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "spendADay",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "test_rand",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "test_limit",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "bool",
                "internalType": "bool"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "randao",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "chance",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    }
]

converter_address='0x5742F2B61093a470a2d69B685f82bD1dd00A5312'
SEPOLIA_WSS_URL = os.environ["SEPOLIA_WSS_URL"]
SEPOLIA_RPC_URL = os.environ["SEPOLIA_RPC_URL"]
w3 = Web3(Web3.HTTPProvider(SEPOLIA_RPC_URL))
assert(w3.is_connected())
pk = os.environ["ETH_ACC_PK_SEPOLIA"]
acc = w3.eth.account.from_key(pk)

def decode_custom_error(w3, contract_abi, error_data):
    for error in [abi for abi in contract_abi if abi["type"] == "error"]:
        # Get error signature components
        name = error["name"]
        data_types = [collapse_if_tuple(abi_input) for abi_input in error.get("inputs", [])]
        error_signature_hex = function_abi_to_4byte_selector(error).hex()
        # Find match signature from error_data
        if error_signature_hex.casefold() == str(error_data.data)[2:10].casefold():
            params = ','.join([str(x) for x in w3.codec.decode(data_types,bytes.fromhex(str(error_data.data)[10:]))])
            decoded = "%s(%s)" % (name , str(params))
            return decoded
    return None

def try_to_buy(converter, w3, height):
    can_buy = False
    failure_reason = None
    try:
        converter.functions.buy().call({'from': acc.address})
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

    logging.info(f"height: {height}, simulation successful?: {can_buy}")
    if not can_buy:
        return failure_reason
    nonce = w3.eth.get_transaction_count(acc.address)
    try:
        unsigned_tx = converter.functions.buy().build_transaction({
            'from': acc.address,
            'nonce': nonce,
            'maxFeePerGas': w3.to_wei(100, 'gwei'),
            'maxPriorityFeePerGas': w3.to_wei(20, 'gwei'),
        })
        signed_tx = w3.eth.account.sign_transaction(unsigned_tx, private_key=acc.key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"{nonce}: https://sepolia.etherscan.io/tx/{tx_hash.hex()}")
    except ContractCustomError as exp:
        failure_reason = decode_custom_error(w3, conv_abi, exp)
        logging.info(f"failed in transact() while being succesful in call() with error: {failure_reason}")
        exit(1)
    except ContractLogicError as exp:
        logging.info(f"Logic: {exp}")
        pass
    except BaseException as exp:
        logging.info(f"BaseException: {exp}")
        pass

async def get_event():
    converter = w3.eth.contract(address=converter_address, abi=conv_abi)
    async with connect(SEPOLIA_WSS_URL) as ws:
        await ws.send(json.dumps({"id": 1, "method": "eth_subscribe", "params": ["newHeads"]}))
        subscription_response = await ws.recv()
        while True:
            message_str = await asyncio.wait_for(ws.recv(), timeout=60)
            message = json.loads(message_str)
            height = int(message["params"]["result"]["number"][2:], 16)
            try_to_buy(converter, w3, height)

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    while True:
        loop.run_until_complete(get_event())
