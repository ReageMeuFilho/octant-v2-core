# Dragon Vault Module

## For using on a new chain

- Duplicate .env.template to .env and fill in the required fields
- Run `script/DeployModuleFactoryToken.s.s.sol` to deploy Module factory, Implementation of Dragon Vault Module and Test Asset.
  ```
  forge script script/DeployModuleFactoryToken.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast -vvvvv
  ```
- Add the deployed addresses to `.env`

## Steps to test with new safe

- Duplicate .env.template to .env and fill in the required fields
- Run `script/CreateSafeWithVaultModule.s.sol` to deploy a new safe with dragon vault module already linked.
  ```
  forge script script/CreateSafeWithVaultModule.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast -vvvvv
  ```
- Add the newly deployed Safe address `SAFE_ADDRESS` and linked dragon vault module address `SAFE_DRAGON_VAULT_MODULE_ADDRESS` to `.env` and run `source .env`
- `script/AddTransactionToSafe.s.sol` contains default transaction to approve Test Asset to the module and deposit in the Dragon Vault Module. modify it if u want to run different transaction.
  ```
  forge script script/AddTransactionToSafe.s.sol --private-key $PRIVATE_KEY --rpc-url $POLYGON_RPC_URL --slow --ffi -vvvvv
  ```
- One can also test the dragon vault module through the safe ui by using `Zodiac` safe app.

## Steps to test with a previous safe

- Run `script/DeployModuleAndEnableOnSafe.s.sol` to deploy a new dragon vault module through Module Factory Proxy and create a transaction to link to safe.
  ```
  forge script script/DeployModuleAndEnableOnSafe.s.sol --private-key $PRIVATE_KEY --rpc-url $POLYGON_RPC_URL --slow --ffi -vvvvv
  ```
- Add linked dragon vault module address `SAFE_DRAGON_VAULT_MODULE_ADDRESS` to `.env` and run `source .env`
- `script/AddTransactionToSafe.s.sol` contains default transaction to approve Test Asset to the module and deposit in the Dragon Vault Module. modify it if u want to run different transaction.
  ```
  forge script script/AddTransactionToSafe.s.sol --private-key $PRIVATE_KEY --rpc-url $POLYGON_RPC_URL --slow --ffi -vvvvv
  ```
- One can also test the dragon vault module through the safe ui by using `Transaction Builder` and `Zodiac` safe app.
