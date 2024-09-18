#!/usr/bin/env python3

import os
import json
import asyncio
from websockets import connect
from uuid import uuid4

import click
from eth_account.account import Account
from eth_account.signers.local import LocalAccount
from flashbots import flashbot
from web3 import Web3, HTTPProvider
from web3.exceptions import ContractCustomError, ContractLogicError, TransactionNotFound

import logging

logging.basicConfig(format="%(asctime)s %(message)s", level=logging.INFO)

relayUrl = "https://relay-sepolia.flashbots.net/"
SEPOLIA_WSS_URL = os.environ["SEPOLIA_WSS_URL"]
SEPOLIA_RPC_URL = os.environ["SEPOLIA_RPC_URL"]
# Create a web3 object with a standard json rpc provider, such as Infura, Alchemy, or your own node.
w3 = Web3(HTTPProvider(SEPOLIA_RPC_URL))

# FLASHBOTS_REPUTATION_KEY is an Ethereum private key that does NOT store funds and is NOT your bot's primary key.
# This is an identifying key for signing payloads to establish reputation and whitelisting
FLASHBOTS_REPUTATION_KEY: LocalAccount = Account.from_key(
    os.environ.get("FLASHBOTS_REPUTATION_KEY")
)

# Flashbots providers require both a standard provider and FLASHBOTS_REPUTATION_KEY (to establish reputation)
w3 = flashbot(w3, FLASHBOTS_REPUTATION_KEY, relayUrl)

assert w3.is_connected()

# This address is used to pay for gas
pk = os.environ["ETH_ACC_PK_SEPOLIA"]
acc = w3.eth.account.from_key(pk)

converter_address = "0x5742F2B61093a470a2d69B685f82bD1dd00A5312"
conv_abi = [
    {
        "inputs": [],
        "name": "buy",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    }
]


def try_to_buy(converter, w3, height, use_mempool):
    can_buy = False
    failure_reason = None
    try:
        converter.functions.buy().call({"from": acc.address})
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

    logging.info(f"height: {height}, can_buy: {can_buy}")
    if not can_buy:
        return failure_reason
    if use_mempool:
        submit_mempool(converter, w3, height)
    else:
        submit_flashbots(converter, w3, height)


def submit_mempool(converter, w3, height):
    nonce = w3.eth.get_transaction_count(acc.address)
    try:
        unsigned_tx = converter.functions.buy().build_transaction(
            {
                "from": acc.address,
                "nonce": nonce,
                "maxFeePerGas": w3.to_wei(100, "gwei"),
                "maxPriorityFeePerGas": w3.to_wei(20, "gwei"),
            }
        )
        signed_tx = w3.eth.account.sign_transaction(unsigned_tx, private_key=acc.key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"{nonce}: https://sepolia.etherscan.io/tx/{tx_hash.hex()}")
    except ContractCustomError as exp:
        failure_reason = decode_custom_error(w3, conv_abi, exp)
        logging.info(
            f"failed in transact() while being succesful in call() with error: {failure_reason}"
        )
        exit(1)
    except ContractLogicError as exp:
        logging.info(f"Logic: {exp}")
        pass
    except BaseException as exp:
        logging.info(f"BaseException: {exp}")
        pass


def submit_flashbots(converter, w3, height):
    nonce = w3.eth.get_transaction_count(acc.address)
    max_pri_gas = w3.eth.max_priority_fee
    try:
        unsigned_tx = converter.functions.buy().build_transaction(
            {
                "from": acc.address,
                "nonce": nonce,
                "maxFeePerGas": w3.to_wei(400, "gwei"),
                "maxPriorityFeePerGas": max_pri_gas + w3.to_wei(10, "gwei"),
            }
        )
    except ContractCustomError as exp:
        failure_reason = decode_custom_error(w3, conv_abi, exp)
        logging.info(
            f"failed in transact() while being succesful in call() with error: {failure_reason}"
        )
        exit(1)
    except ContractLogicError as exp:
        logging.info(f"Logic: {exp}")
        return
    except BaseException as exp:
        logging.info(f"BaseException: {exp}")
        return

    signed_tx = w3.eth.account.sign_transaction(unsigned_tx, private_key=acc.key)
    bundle = [{"signed_transaction": signed_tx.rawTransaction}]
    send_result = w3.flashbots.send_bundle(
        bundle,
        target_block_number=height + 1,
    )
    bundle_hash = w3.to_hex(send_result.bundle_hash())
    stats_v1 = w3.flashbots.get_bundle_stats(bundle_hash, height + 1)
    logging.info(f"Stats_v1  {stats_v1}")
    stats_v2 = w3.flashbots.get_bundle_stats_v2(bundle_hash, height + 1)
    logging.info(f"Stats_v2  {stats_v2}")
    send_result.wait()
    try:
        receipts = send_result.receipts()
        logging.info(f"Bundle was mined in block {receipts[0].blockNumber}")
        return
    except TransactionNotFound:
        logging.info(f"Bundle not found in block {height+1}")


async def get_event(use_mempool):
    converter = w3.eth.contract(address=converter_address, abi=conv_abi)
    async with connect(SEPOLIA_WSS_URL) as ws:
        await ws.send(
            json.dumps({"id": 1, "method": "eth_subscribe", "params": ["newHeads"]})
        )
        subscription_response = await ws.recv()
        while True:
            try:
                message_str = await asyncio.wait_for(ws.recv(), timeout=60)
            except:
                continue
            message = json.loads(message_str)
            height = int(message["params"]["result"]["number"][2:], 16)
            try_to_buy(converter, w3, height, use_mempool)


@click.command
@click.option(
    "-m",
    "--mempool",
    is_flag=True,
    default=False,
    help="Use mempool instead of going through flashbots",
)
def main(mempool):
    loop = asyncio.new_event_loop()
    while True:
        loop.run_until_complete(get_event(mempool))


if __name__ == "__main__":
    main()
