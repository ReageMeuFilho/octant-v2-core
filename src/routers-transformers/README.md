# Trader.sol

## Executive summary
Trader is a contract that allows its deployer to DCA into a token (quote token) in terms of base token at random times. In situation when there exist a separation between principal and agent (as in company and employee situation) Trader allows agent to convert one token into other in a way which precludes accusation of insider trading. Agent (the deployer) is on equal terms with everyone else w.r.t knowledge of when trades will occur. Other useful functionality offered by Trader is long-term automation of the process.

### Core functionality
1. DCA at random times on a pair of tokens.
   Base token is spent at some average rate to buy quote token. Moments when trades can be made are decided by blockhash of block. Potential weakness of blockhash as randomness source is addressed by spending speed limit set from above and Ethereum mainnet censorship resistance guarantees from below.
2. Respects deadlines.
   Trader will spent its *budget* before a *deadline*. Deadlines occur at the end of each *period*. A single *budget* will be spent in a single *period*. Notion of budget is different from amount of base token held by the Trader.
3. Driven by MEV searchers.
   MEV searchers are incentivised to execute trades, sending transactions, paying for gas and getting whatever MEV they can get. Contract attempts to control how much MEV can be extracted by utilizing TWAP oracle for price information.

### Responsibilities
`Trader.sol` implements triggering at random times, periods, budgets, deadlines and overspending protection. It doesn't directly integrate with an exchange. This responsibility outsourced to a pair of contracts. `UniV3Swap.sol` does trading via Uniswap V3 and `SwapperImpl.sol` does consult the TWAP oracle and makes sure principal (`beneficiary` in Trader's parlance) is not being short-changed during the trade. Both contracts are a part of [0xSplits project](https://github.com/0xSplits/splits-swapper/). They are denoted as `integrator` and `swapper` inside `Trader.sol`.

Trader exposes two sets of interfaces. One is `transform(...)`, as defined in `ITransformer.sol`. It is supposed to be called downstream of a call to router's `claimSplit(...)`. Example of its usage is in `TraderBotEntry.sol` contract. Other is `convert(...)`, and it accepts block height. If succesful, it will send some amount of base token to `swapper` address. Convert is internally used by `transform(...)`.

### Randomness design
