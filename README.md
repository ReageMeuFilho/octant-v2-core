## Installation

1. Clone the repository:

```bash
# Clone with submodules in one command
git clone --recurse-submodules https://github.com/golemfoundation/octant-v2-core.git
cd octant-v2-core

# Or clone and init submodules separately
git clone https://github.com/golemfoundation/octant-v2-core.git
cd octant-v2-core
git submodule update --init --recursive
```

2. Install dependencies:

```bash
# Initialize and update all submodules
git submodule update --init --recursive

# Install Foundry dependencies
forge install

# Install Node.js dependencies
corepack enable
yarn install
```

3. Configure environment:

Setup lint hooks
```bash
yarn init
```

Copy the environment template
```bash
cp .env.template .env

# Edit .env with your configuration
# Required fields:
# - RPC_URL: Your RPC endpoint
# - PRIVATE_KEY: Your wallet private key
# - ETHERSCAN_API_KEY: For contract verification
# - Other fields as needed for your use case
```

## Documentation

https://book.getfoundry.sh/

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
