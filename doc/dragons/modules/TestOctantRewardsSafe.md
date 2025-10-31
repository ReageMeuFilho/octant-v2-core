# Testing Octant Rewards Safe Module

## For using on a new chain

- Duplicate .env.template to .env and fill in the required fields
- Run `script/DeployOctantModuleFactory.s.sol` to deploy Module factory, Implementation of Dragon Vault Module and Test Asset.
  ```
  forge script script/DeployOctantModuleFactory.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast -vvvvv
  ```
- Add the deployed addresses to `.env`

## Steps to test with new safe

- Duplicate .env.template to .env and fill in the required fields
- Run `script/CreateSafeWithOctantRewardsSafeModule.s.sol` to deploy a new safe with dragon vault module already linked.
  ```
  forge script script/CreateSafeWithOctantRewardsSafeModule.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast -vvvvv
  ```
- Call harvest on the module through etherscan / using `Zodiac` safe app.

## Steps to test with a previous safe

- Run `script/DeployOctantModuleAndEnableOnSafe.s.sol` to deploy a new octant vault module through Module Factory Proxy and create a transaction to link to safe.
  ```
  forge script script/DeployOctantModuleAndEnableOnSafe.s.sol --private-key $PRIVATE_KEY --rpc-url $POLYGON_RPC_URL --slow --ffi -vvvvv
  ```
- Call harvest on the module through etherscan / using `Zodiac` safe app.
