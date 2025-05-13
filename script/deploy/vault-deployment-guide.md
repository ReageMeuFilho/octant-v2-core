# Vault Deployment Guide

This guide explains how to deploy the Vault ecosystem using Foundry scripts.

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Access to an Ethereum RPC endpoint
- Private key with sufficient ETH for deployment

## Setup Environment

For security, we use environment variables to store sensitive information like private keys:

```bash
# Set your private key as an environment variable (replace with your actual key)
export PRIVATE_KEY=0x123abc...

# Alternatively, you can create a .env file and load it
echo "PRIVATE_KEY=0x123abc..." > .env
source .env
```

## Scripts Overview

We have two deployment scripts:

1. **DeployVaultFactory.s.sol** - Deploys the VaultFactory contract
2. **DeployVault.s.sol** - Deploys individual vaults using an existing VaultFactory

Both scripts automatically access your private key using `vm.envUint("PRIVATE_KEY")`.

## Deploying the VaultFactory

First, you need to deploy the VaultFactory which serves as the factory for creating new vaults.

### Command

```bash
forge script script/deploy/DeployVaultFactory.s.sol --rpc-url <YOUR_RPC_URL> --broadcast 
```

### Input Parameters

During execution, the script will prompt for:

- **Vault Implementation**: Address of an existing vault implementation or "no" to deploy a new one
- **Factory Name**: Name for the VaultFactory
- **Governance Address**: Address that will have governance privileges

### Output

The script will output:
- Vault implementation address
- VaultFactory address
- Configuration details

## Deploying Vaults

After the VaultFactory is deployed, you can create new vaults.

### Single Vault Deployment

```bash
forge script script/deploy/DeployVault.s.sol --rpc-url <YOUR_RPC_URL> --broadcast
```

### Multiple Vault Deployment

To deploy multiple vaults in a single transaction:

```bash
forge script script/deploy/DeployVault.s.sol:DeployVaults --sig "deployMultipleVaults(uint256)" <NUMBER_OF_VAULTS> --rpc-url <YOUR_RPC_URL> --broadcast
```

### Input Parameters

For single vault deployment, you'll be prompted for:
- **VaultFactory Address**: Address of the previously deployed factory
- **Asset Address**: The underlying token address
- **Vault Name**: Name for the vault token
- **Vault Symbol**: Symbol for the vault token
- **Role Manager Address**: Address that will manage roles
- **Profit Max Unlock Time**: Time period in seconds over which profits unlock (default: 604800 - 7 days)

For multiple vault deployment, you'll first be prompted for:
- **VaultFactory Address**: Address of the factory
- **Role Manager Address**: Common address for all vaults
- **Profit Max Unlock Time**: Common setting for all vaults

Then for each vault:
- **Asset Address**: The underlying token address
- **Vault Name**: Name for the vault token
- **Vault Symbol**: Symbol for the vault token

### Output

The script will output:
- Deployed vault address(es)
- Verification of vault parameters




