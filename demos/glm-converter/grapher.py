#!/usr/bin/env python3

import asyncio
import json
import os
import requests
from websockets import connect

from dataclasses import dataclass, field

from eth_utils.abi import function_abi_to_4byte_selector, collapse_if_tuple
from web3 import Web3
from web3.exceptions import ContractCustomError, ContractLogicError

import logging
logging.basicConfig(format='%(asctime)s %(message)s', level=logging.INFO)

token_abi = [
    {
        "type": "function",
        "name": "balanceOf",
        "inputs": [{
            "name": "",
            "type": "address",
            "internalType": "address"
        }],
        "outputs": [
            {
                "name": "",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "stateMutability": "view"
    },
]

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
        "name": "WETHAddress",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "GLMAddress",
        "inputs": [],
        "outputs": [
            {
                "name": "",
                "type": "address",
                "internalType": "address"
            }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "blocksADay",
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
        "name": "lastQuota",
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
conv = w3.eth.contract(address=converter_address, abi=conv_abi)
weth_address=conv.functions.WETHAddress().call()
weth = w3.eth.contract(address=weth_address, abi=token_abi)
glm_address=conv.functions.GLMAddress().call()
glm = w3.eth.contract(address=glm_address, abi=token_abi)
blocks_a_day = conv.functions.blocksADay().call()


@dataclass
class ConvStatus:
    spent: int # WETH, wei
    spendable: int # WETH, wei
    weth_balance: int
    glm_balance: int
    price: int # price of 1 ETH in GLMs, wei
    last_quota: int # price of 1 ETH in GLMs, wei

def log_status(height: int, sts: ConvStatus):
    print(f"{height},{sts.spent},{sts.spendable},{sts.weth_balance},{sts.glm_balance},{sts.price},{sts.last_quota}")

def get_status(conv, w3, height):
    spent = conv.functions.spent().call()
    starting_block = conv.functions.startingBlock().call()
    spend_a_day = conv.functions.spendADay().call()
    spendable = int((height - starting_block) * (spend_a_day / blocks_a_day))
    return ConvStatus(
        spent=spent,
        spendable=spendable,
        weth_balance=weth.functions.balanceOf(converter_address).call(),
        glm_balance=glm.functions.balanceOf(converter_address).call(),
        price=conv.functions.price().call(),
        last_quota=conv.functions.lastQuota().call()
    )

async def get_event():
    async with connect(SEPOLIA_WSS_URL) as ws:
        await ws.send(json.dumps({"id": 1, "method": "eth_subscribe", "params": ["newHeads"]}))
        subscription_response = await ws.recv()
        while True:
            try:
                message_str = await asyncio.wait_for(ws.recv(), timeout=60)
            except:
                continue
            message = json.loads(message_str)
            height = int(message["params"]["result"]["number"][2:], 16)
            status = get_status(conv, w3, height)
            log_status(height, status)

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    while True:
        loop.run_until_complete(get_event())
