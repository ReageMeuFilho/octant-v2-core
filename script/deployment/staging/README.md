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
SAFE_SINGLETON - Safe singleton address
SAFE_PROXY_FACTORY - Safe proxy factory address
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
4. Create `.env` file
   ```
   PRIVATE_KEY=(deployer private key ex. MetaMask account)
   VERIFIER_API_KEY=(your Personal Tenderly accessToken)
   RPC_URL=https://rpc.ov2st.octant.build
   VERIFIER_URL=$RPC_URL/verify/etherscan
   SAFE_SINGLETON=0x41675C099F32341bf84BFc5382aF534df5C7461a
   SAFE_PROXY_FACTORY=0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67
   MAX_OPEX_SPLIT=5 # to confirm
   MIN_METAPOOL_SPLIT=0 # to confirm
   
   ```

5. Run script in terminal (repo root) 
   ```shell
     source .env
     # Deploy V2 Contracts
     forge script script/deployment/staging/DeployProtocol.s.sol --slow --verify -vvvv -f $RPC_URL --private-key $PRIVATE_KEY --broadcast
     # Deploy Hats Protocol - if lib error occurs change ERC1155 import to relative lib/hats-protocol/src/Hats.sol:19 -> import { ERC1155 } from "../lib/ERC1155/ERC1155.sol";
     forge script lib/hats-protocol/script/Hats.s.sol:DeployHats --slow --verify -vvvv -f $RPC_URL --private-key $PRIVATE_KEY --broadcast
     
   ```
