At Runtime Verification, we specialize in building rigorous, mathematically grounded proofs to ensure that smart contracts behave as intended under all possible inputs and scenarios. Our tool, Kontrol, is designed to integrate seamlessly with Solidity-based projects, enabling developers to write property-based tests in Solidity and leverage symbolic execution to verify them.

The first step when formally verifying a protocol is to identify the main invariants that the protocol should hold under all circumstances. In the case of Octant V2 Core the main invariant is: 
**"Separate yield from principal: Users deposit assets and receive 1:1 vault tokens and the asset-to-share ratio should remain constant (1:1)."**

## Proving with  Kontrol
After identifying the protocol's main invariant, the next step was to translate it into solidity and write Kontrol proofs that ensure the invariant holds in every possible state. The asset-to-share ratio remains constant (1:1) if the total supply of the protocol remains equal to the total assets. This was translated into solidity as follows:

```solidity
function principalPreservationInvariant(Mode mode) internal view {
    uint256 totalSupply = strategy.totalSupply();
    uint256 totalAssets = strategy.totalAssets();

    if (mode == Mode.Assume) {
        vm.assume(totalSupply == totalAssets);
    } else {
       assert(totalSupply == totalAssets);
    }
}
```

To formally prove that some invariant holds it is necessary to prove that:

#### 1. The invariant holds in the initial state
This is trivially true because when contracts are deployed, `strategy.totalSupply() == 0` and `strategy.totalAssets() == 0`; therefore, `totalSupply == totalAssets` is true.
#### 2. For every pre-state, if the invariant holds in that state, then after a state transition, the invariant must still hold in the post-state
To prove this, it is necessary to prove that, for every function that can potentially change the state, if the invariant holds before calling the function, it must still hold after the function execution. Therefore, for every (external or public) function that can potentially change the state, there is a test with the following structure:

```solidity
function testStrategyFunction(args) public {
    principalPreservationInvariant(Mode.Assume);

    contract.publicOrExternalFunction(params);

    principalPreservationInvariant(Mode.Assert);
}
```
### Symbolic Execution
When running the above test with Kontrol, the `args` are symbolic, which means that we prove the invariant holds for every possible input the function can take, whereas, with Foundry, we only prove that the invariant holds for the specific concrete `args` the test runs with. 
Notice that we still need to define what "For every possible state" means. Foundry allows us to define an initial pre-state (with the `setUp` function) to run the tests. However, that initial pre-state is concrete, which means that we would be proving the above invariant to a particular pre-state. In Kontrol, we have the `symbolicStorage` cheatcode, which makes the storage of a given contract fully symbolic. Therefore, when setting up the pre-state state to run the proofs, after deploying the strategy contract, we call `kevm.symbolicStorage(address(strategy))`, making the initial pre-state as abstract as possible.
After the symbolic `setUp`, if the specified proofs pass with Kontrol, we prove that the invariant holds in every possible state of the protocol.

### Kontrol Proofs
To prove the main invariant, we defined the following tests with the above structure:

- `testDeposit`
- `testDepositWithLockup`
- `testMint`
- `testMintWithLockup`
- `testWithdraw`
- `testRedeem`
- `testTend`

With respect to the `report` function we can only prove that the invariant holds if we can assume there is no loss in the protocol, i.e., the dragon Router shares are enough to cover the loss of assets. Therefore, we wrote two proofs:

- `testReport` - proves the invariant holds when assuming there is no loss in the protocol
- `testReportWithLoss` - if there is a loss in the protocol, then `strategy.totalSupply() > strategy.totalAssets()`

We also proved that a user cannot withdraw funds if their lockup hasn't expired:
- `testWithdrawRevert`
- `testRedeemRevert`

Aditionally, we also specified some tests for access control functions:
- `testSetPendingManagement`
- `testSetKeeper`
- `testSetEmergencyAdmin`

Finally, for the `deposit` and `mint` functions, we also asserted some state-expected changes after the function execution.

### Reproducing the Proofs
To reproduce the results of this verification locally, follow the steps below:

1. Install Kontrol
```bach
bash <(curl https://kframework.org/install)
kup install kontrol
```
2. Run the Proofs
```bash
export FOUNDRY_PROFILE=kprove
kontrol build
kontrol prove
```
The `kontrol.toml` file contains a set of flags to run Kontrol with. Refer to the Kontrol [documentation](https://docs.runtimeverification.com/kontrol) if you want to learn more about Kontrol options. 