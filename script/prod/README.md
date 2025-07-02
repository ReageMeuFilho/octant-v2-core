# Dragon Protocol Deployment Guide

This guide explains how to deploy the Dragon Protocol core components in a Development environment or in your own Tenderly Sepolia Testnet (look at the end).

## Overview

The DeployProtocol script handles the sequential deployment of:

1. Safe (1/1 multisig)
2. Module Proxy Factory
3. Hats Protocol & Dragon Hatter
4. Dragon Tokenized Strategy Implementation
5. Dragon Router
6. Mock Strategy (for testing)

## Prerequisites

- Access to an RPC endpoint for your target network
- Private key with sufficient native tokens for deployment
- Environment file (.env) setup

## Environment Setup

Your .env file should contain:

```
PRIVATE_KEY - Your deployment private key
RPC_URL - URL for your target network
ETHERSCAN_API_KEY - For contract verification
```

## Running the Deployment

1. First dry run the deployment:
   ```forge script script/prod/DeployProtocol.s.sol:DeployProtocol -vvvv --rpc-url $RPC_URL```

2. If the dry run succeeds, execute the actual deployment:
   ```forge script script/prod/DeployProtocol.s.sol:DeployProtocol --rpc-url $RPC_URL --broadcast --verify```

## Post Deployment

The script will output a deployment summary with all contract addresses. Save these addresses for future reference.

The script performs automatic verification of:
- Safe configuration
- Owner permissions
- Strategy enablement
- Component connections

## Security Considerations

- The initial Safe is deployed as 1/1 for simplicity but should be upgraded to a proper multisig after deployment
- All contract ownership and admin roles are initially assigned to the deployer
- Additional owners and permissions should be configured after successful deployment
- Verify all addresses and permissions manually after deployment

## Next Steps

After successful deployment:
1. Configure multisig owners
2. Set up etra permissions on hats protocol
4. Deposit into strategy and mint undelying asset token
## How to create your own Sepolia Virtual TestNet in Tenderly and deploy V2 contracts there:

1. Create your own Virtual TestNet in Tenderly (Sepolia, sync on) (https://docs.tenderly.co/virtual-testnets/quickstart)
2. Create Tenderly Personal accessToken (https://docs.tenderly.co/account/projects/how-to-generate-api-access-token#personal-account-access-tokens)
3. Send some SepoliaETH (your own Sepolia TestNet RPC) to your deployer address (ex. MetaMask account) (https://docs.tenderly.co/virtual-testnets/unlimited-faucet)
4. Set required ENVs

```
SENDER=(deployer address ex. MetaMask account)PRIVATE_KEY=(deployer private key ex. MetaMask account)
THRESHOLD=1 # Safe threshold (default is 5)
TENDERLY_VIRTUAL_TESTNET_RPC_URL=(your own Sepolia TestNet RPC)
TENDERLY_VERIFIER_URL=$TENDERLY_VIRTUAL_TESTNET_RPC_URL/verify/etherscan
TENDERLY_ACCESS_TOKEN=(your Personal Tenderly accessToken)
MAX_OPEX_SPLIT=5 # to confirm
MIN_METAPOOL_SPLIT=0 # to confirm
GOVERNANCE=$SENDER # to confirm
```

3. Run script in terminal (repo root)
    1. `source .env`
    2. ```forge script script/prod/DeployProtocol.s.sol --slow --verify --verifier-url $TENDERLY_VERIFIER_URL --sender $SENDER --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $TENDERLY_ACCESS_TOKEN -vvvv --broadcast``` // Deploy V2 Contracts
    3. ```forge script dependencies/hats-protocol-1.0/script/Hats.s.sol:DeployHats --slow --verify --verifier-url $TENDERLY_VERIFIER_URL --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $TENDERLY_ACCESS_TOKEN -vvvv --broadcast``` // Deploy Hats Protocol
