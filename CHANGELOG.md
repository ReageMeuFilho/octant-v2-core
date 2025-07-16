

## [0.6.0-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.11-develop.0...v0.6.0-develop.0) (2025-07-16)


### Features

* add missing admin and user functions to RegenStakerWithoutDelegateSurrogateVotes ([1469e8a](https://github.com/golemfoundation/octant-v2-core/commit/1469e8a103e20c029174b1edab735aefd2751f2a))
* add missing contribute function to RegenStakerWithoutDelegateSurrogateVotes ([1b239d1](https://github.com/golemfoundation/octant-v2-core/commit/1b239d141b33f17bd5258b1bc3e221a9ab9e70c1))
* **allocation:** add token sweep functionality after grace period ([057681f](https://github.com/golemfoundation/octant-v2-core/commit/057681fdf8bd216ab57f1029d1e76029cee61f77))
* implement two-step ownership transfer to prevent permanent lock ([a7624a2](https://github.com/golemfoundation/octant-v2-core/commit/a7624a2a5e16d47ab3825ceef5d85cc7ddfdc7ed))
* improve RegenStaker contribute function security and API ([4929e06](https://github.com/golemfoundation/octant-v2-core/commit/4929e066a2df03e6b7f441f20eb2bf33d4c149f1))
* introduce signUpOnBehalf ([666e9e6](https://github.com/golemfoundation/octant-v2-core/commit/666e9e65bf0115a4d7733b12d3f0b2e757715173))
* **qf:** add optimal alpha calculation for 1:1 share ratio ([bc4d340](https://github.com/golemfoundation/octant-v2-core/commit/bc4d34012b9fbde492e8affddc05bcb0cb8fb936))
* **qf:** implement whitelist-controlled quadratic funding mechanism ([3b845e3](https://github.com/golemfoundation/octant-v2-core/commit/3b845e3404523d792d1149412ac53d832d4c4d88))
* **strategy:** add optimal alpha calculation for quadratic funding ([a17ee53](https://github.com/golemfoundation/octant-v2-core/commit/a17ee53ce42ce6b5bf1e710d517876499695e544))
* **voting:** restrict proposal creation to keeper/management roles ([7092582](https://github.com/golemfoundation/octant-v2-core/commit/7092582a38b1e76af108a983f72d5c40f23cf254))


### Bug Fixes

* address final audit finding in _claimReward ([fe4c3f5](https://github.com/golemfoundation/octant-v2-core/commit/fe4c3f5f347864b731dfce03160089ffa4958489))
* **auth:** restrict hook access to delegatecall only ([31336ab](https://github.com/golemfoundation/octant-v2-core/commit/31336ab843585c3786cae7a3027f6a9ad2152b09))
* **funding:** update total funding calculation to use weighted formula ([1e32fe8](https://github.com/golemfoundation/octant-v2-core/commit/1e32fe8146866b8a4e373d43a388c374a11817f7))
* onlyRegenGovernance in MultistrategyLockedVault ([206d7d3](https://github.com/golemfoundation/octant-v2-core/commit/206d7d345d7d5c8c7fa2852e05307eccfac46320))
* prevent ETH permanent fund loss by rejecting ETH deposits ([4ce82fc](https://github.com/golemfoundation/octant-v2-core/commit/4ce82fc0a8a68238c8a9798fa6936b21363605f4))
* prevent share dilution attack through delayed proposal queueing ([d435b13](https://github.com/golemfoundation/octant-v2-core/commit/d435b13466446454b002ac1baaff8975b8b9df79))
* prevent zero voting power registration from decimal scaling ([76ddbde](https://github.com/golemfoundation/octant-v2-core/commit/76ddbde8a4d3530d8bc13a58a6fcba843dcdd622))
* **ProperQF:** resolve overflow in quadratic calculations for 18-decimal token ([541fbc7](https://github.com/golemfoundation/octant-v2-core/commit/541fbc781d7f8ec5a2372e8126daa7524fdca5b5))
* refine zero voting power check to allow zero-deposit registrations ([d76a03a](https://github.com/golemfoundation/octant-v2-core/commit/d76a03af19d3b249f85d66c8ff4fed9784832b2b))
* remove balance adjustment in _withdraw for accurate previewRedeem ([8936b91](https://github.com/golemfoundation/octant-v2-core/commit/8936b914f71ac1cc0f1e285a87ede6d11c69f050))
* **security:** prevent whitelist circumvention via delegation ([1a0c922](https://github.com/golemfoundation/octant-v2-core/commit/1a0c922fea29c7bb1bfb95d89a8fe2f826bd09d7))


### Reverts

* Revert "Revert "refactor(QuadraticVoting): simplify _availableWithdrawLimit"" ([1226206](https://github.com/golemfoundation/octant-v2-core/commit/12262067758007f3334475f6de90ec519f7b4892))
* Revert "refactor(QuadraticVoting): simplify _availableWithdrawLimit" ([941e84d](https://github.com/golemfoundation/octant-v2-core/commit/941e84dd457279fe3ea126a2de7561cea39fd8b5))

## [0.5.11-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.10-develop.0...v0.5.11-develop.0) (2025-07-10)

## [0.5.10-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.9-develop.0...v0.5.10-develop.0) (2025-07-10)

## [0.5.9-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.8-develop.0...v0.5.9-develop.0) (2025-07-09)

## [0.5.8-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.7-develop.0...v0.5.8-develop.0) (2025-07-09)

## [0.5.7-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.6-develop.0...v0.5.7-develop.0) (2025-07-09)

## [0.5.6-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.5-develop.0...v0.5.6-develop.0) (2025-07-09)

## [0.5.5-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.4-develop.0...v0.5.5-develop.0) (2025-07-09)

## [0.5.4-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.3-develop.0...v0.5.4-develop.0) (2025-07-09)

## [0.5.3-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.2-develop.0...v0.5.3-develop.0) (2025-07-09)

## [0.5.2-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.1-develop.0...v0.5.2-develop.0) (2025-07-09)

## [0.5.1-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.5.0-develop.0...v0.5.1-develop.0) (2025-07-08)


### Bug Fixes

* prevent CREATE3 front-running attacks in strategy factories ([c3653ee](https://github.com/golemfoundation/octant-v2-core/commit/c3653ee94d9aa150adf28e07b61ff0b3024e6831))
* use decimalsOfExchangeRate for proper exchange rate scaling ([60638e9](https://github.com/golemfoundation/octant-v2-core/commit/60638e9f33672fe83a7cd619ab15ca2602c02a9a))

## [0.5.0-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.4.0-develop.0...v0.5.0-develop.0) (2025-07-03)


### Features

* add enableBurning flag to TokenizedStrategy ([952397e](https://github.com/golemfoundation/octant-v2-core/commit/952397e11d54980919ab422664ad71d5d30881c9))
* add loss tracker to TokenizedStrategy ([dd6dfd4](https://github.com/golemfoundation/octant-v2-core/commit/dd6dfd440764085ac59d0b69dbebf6f26d15dc6a))
* create BaseYieldSkimmingStrategy ([bcc94d2](https://github.com/golemfoundation/octant-v2-core/commit/bcc94d2352311856c8ad14f0323864a029d023b5))
* create IYieldSkimmingStrategy interface ([7875aa6](https://github.com/golemfoundation/octant-v2-core/commit/7875aa665f55cfc6b611cd6be469cbed22b19ced))
* ERC20SafeApproveLib ([ad52b9a](https://github.com/golemfoundation/octant-v2-core/commit/ad52b9a8eff38d7518396a5aa567c4b9ed577b4d))
* **events:** add donation tracking events for transparent yield flow monitoring ([829109c](https://github.com/golemfoundation/octant-v2-core/commit/829109c075f1ecc0a14a85b840dd7182ea47aecc))
* implement burning logic in yield strategies ([00f9ba1](https://github.com/golemfoundation/octant-v2-core/commit/00f9ba11bf40e4a53e81fa3bc4c2cdf541abf866))
* remove ERC20SafeLib after consolidating safe operations ([1256147](https://github.com/golemfoundation/octant-v2-core/commit/125614793ab4322b1597938bc8f374f66fc8e201))
* **security:** implement constructor-based bytecode canonicalization for RegenStakerFactory ([f476b26](https://github.com/golemfoundation/octant-v2-core/commit/f476b266c1c1fe3c7083b9e6d065ba2b4d8ad963))
* **strategies:** implement loss tracking mechanism for yield skimming strategies ([ef5f87b](https://github.com/golemfoundation/octant-v2-core/commit/ef5f87b693b10c468f7645a9be9da9631b6532f9))
* update BaseStrategy to pass enableBurning parameter ([eca769a](https://github.com/golemfoundation/octant-v2-core/commit/eca769a5b869ccb029b0ea86d882e5526ac702ea))
* update concrete strategies for enableBurning parameter ([bb9c019](https://github.com/golemfoundation/octant-v2-core/commit/bb9c0192787cbe5c829889081d52657e4a79f97a))
* update health check classes for enableBurning parameter ([8b475b8](https://github.com/golemfoundation/octant-v2-core/commit/8b475b8651cafb17fdab83d844eba0436f06beb3))
* update LidoStrategy with BaseYieldSkimming ([72ee74c](https://github.com/golemfoundation/octant-v2-core/commit/72ee74cd2f3122fda00d5366ff3534ed0a223d19))
* update MorphoCompounderStrategy with BaseYieldSkimming ([6810af7](https://github.com/golemfoundation/octant-v2-core/commit/6810af77b833316620115de49f5b9e814370ed46))
* update RocketPoolStrategy with BaseYieldSkimming ([125c2bb](https://github.com/golemfoundation/octant-v2-core/commit/125c2bbc93c1d411da30612ddf4d59e916ab4606))
* update strategy factories to include enableBurning parameter ([5d73d2e](https://github.com/golemfoundation/octant-v2-core/commit/5d73d2ea4b8ca0d5a07106931a23104916c29a05))


### Bug Fixes

* **rounding:** resolve share calculation inconsistency in withdrawal operations ([4e5b727](https://github.com/golemfoundation/octant-v2-core/commit/4e5b727d97e626aeaf69a450d57c2ae8ade8a538))
* **security:** remove inappropriate Yearn governance control from yield skimming strategies ([c81abcd](https://github.com/golemfoundation/octant-v2-core/commit/c81abcd323da5f25e4a93d8d82169ec861ba8063))
* use actual deposit amount in debt calculation ([b84d3a6](https://github.com/golemfoundation/octant-v2-core/commit/b84d3a6284fd746499876a98e94415f0d5a8e5e7))
* **yield-skimming:** implement proper _harvestAndReport return value in BaseYieldSkimmingStrategy ([7a3e024](https://github.com/golemfoundation/octant-v2-core/commit/7a3e024eb273579bb4ccca202af5402280dbf170))


### Reverts

* Revert "chore: add dry-run deployment of staging env to PR and push pipelines" ([a6a2c5b](https://github.com/golemfoundation/octant-v2-core/commit/a6a2c5b192c59a2f0fe85238632564f7f4acf6c6))

## [0.4.0-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.3.0-develop.1...v0.4.0-develop.0) (2025-06-27)


### Features

* **regen:** enhance factory for vanity address generation and document precision implications ([c433d8b](https://github.com/golemfoundation/octant-v2-core/commit/c433d8ba56c173ce97dd9804f41dab8f6ca040fe))
* **strategies:** add availableWithdrawLimit to SkyCompounderStrategy ([8d553c5](https://github.com/golemfoundation/octant-v2-core/commit/8d553c53b9f015f4e1cad2b9e420f61bdc1c5fd9))


### Bug Fixes

* **regen:** check if allocation mechanism is whitelisted ([93a15b0](https://github.com/golemfoundation/octant-v2-core/commit/93a15b0bc0b463c32b48e90e0f6cff919dffb02a))
* **regen:** don't avoid zero amount for notify reward ([5420356](https://github.com/golemfoundation/octant-v2-core/commit/54203561ca7bcd7701b688e3e3131cfe64be68c8))
* **regen:** don't start whitelists enabled ([a4f350b](https://github.com/golemfoundation/octant-v2-core/commit/a4f350bbca2faab420e8d90ebc2b3524a6fff205))
* **regen:** factory ([a2209c6](https://github.com/golemfoundation/octant-v2-core/commit/a2209c6e1e5bd9c20e12291ffb1dc4453612a845))
* **strategies:** correct type mismatch in MorphoCompounderStrategy emergency withdraw ([d062222](https://github.com/golemfoundation/octant-v2-core/commit/d06222282c7deef4e3d758f29a7ee0e213aabfe4))
* **strategies:** improve loss protection rounding in YieldDonatingTokenizedStrategy ([5be1def](https://github.com/golemfoundation/octant-v2-core/commit/5be1def7497ed6f48f8f01c39841388f0f9abfb4))

## [0.3.0-develop.1](https://github.com/golemfoundation/octant-v2-core/compare/v0.3.0-develop.0...v0.3.0-develop.1) (2025-06-23)


### Features

* **allowance:** add abstract executor with test implementation ([e15ae52](https://github.com/golemfoundation/octant-v2-core/commit/e15ae523395f4f6b2b38a553a38edcd3cfe9d05c))
* **allowance:** add abstract executor with test implementation ([ac14cf4](https://github.com/golemfoundation/octant-v2-core/commit/ac14cf48463c541d5eb39640c2873a2f420e5e91))
* **allowance:** add emergency revoke allowance functionality ([ee6011f](https://github.com/golemfoundation/octant-v2-core/commit/ee6011f39e23fc54c036077e5321a450691aa806))
* **allowance:** add emergency revoke allowance functionality ([24c13c1](https://github.com/golemfoundation/octant-v2-core/commit/24c13c16119216a34b7e47c0d3776daf684af79c))
* **auth:** add EIP712 signature support for signup and voting ([b3d28f0](https://github.com/golemfoundation/octant-v2-core/commit/b3d28f0f3d5119709da1b4e2acac80d4d908176e))
* create BaseYieldSkimmingHealthCheck ([a12a6a5](https://github.com/golemfoundation/octant-v2-core/commit/a12a6a51b4026e3a77b61aed8e0853d1e32a597e))
* create BaseYieldSkimmingStrategy ([d424a39](https://github.com/golemfoundation/octant-v2-core/commit/d424a39e2155f235c8d1e4501085849df121899f))
* create batch functions in LinearAllowanceSingletonForGnosisSafe ([afce643](https://github.com/golemfoundation/octant-v2-core/commit/afce643ce4a409045b562663cb4e8a45a6a0af2c))
* create getMaxWithdrawableAmount() in LinearAllowanceSingletonForGnosisSafe ([86f7c74](https://github.com/golemfoundation/octant-v2-core/commit/86f7c7491ea34f62d88d16a422d92797687ecf39))
* create RocketPoolStrategy ([d9b80ed](https://github.com/golemfoundation/octant-v2-core/commit/d9b80edc84ec5b881a0117db1a87fdda3649e915))
* create RocketPoolStrategyVaultFactory ([317ee74](https://github.com/golemfoundation/octant-v2-core/commit/317ee74ae16dc5b7e8b419e6ba74f0be9c5b23e6))
* **husky:** add slither check ([3e3b45b](https://github.com/golemfoundation/octant-v2-core/commit/3e3b45b28b63afd33c2455cddcbaa7da645e85e1))
* introduce 2 steps donationAddress change ([3804d4a](https://github.com/golemfoundation/octant-v2-core/commit/3804d4a61b586f0aaa72d050b8794c70b608d2c6))
* **mechanisms:** implement tokenized allocation pattern using Yearn V3 style proxy ([61f0740](https://github.com/golemfoundation/octant-v2-core/commit/61f074060b274284ce77c669627b16a9116ff48b))
* **regen:** compounding ([8bdf9cd](https://github.com/golemfoundation/octant-v2-core/commit/8bdf9cde2da773254952adf047eaff6d58814c80))
* **security:** add zero address validation for allowance module ([19663f4](https://github.com/golemfoundation/octant-v2-core/commit/19663f470eb82714579da8e75d42aa229c361d60))


### Bug Fixes

* **allowance:** check post condition of beneficiary as a signal of success ([595ee3f](https://github.com/golemfoundation/octant-v2-core/commit/595ee3f8e2ccc5d21a1be2fa45ab2c589f3dc994))
* **allowance:** fix all the findings and more, refactor and cleanup ([877efef](https://github.com/golemfoundation/octant-v2-core/commit/877efef01398400869bbdbce1eadc269a9b11f9f))
* **allowance:** handle uint160 overflow in drip rate calculation ([da33177](https://github.com/golemfoundation/octant-v2-core/commit/da33177c64605ad4a12b2ee00fab9744e8803e74))
* **allowance:** linter ([87f497a](https://github.com/golemfoundation/octant-v2-core/commit/87f497a193267c5d0e13da3844d64500430c03ef))
* **allowance:** prevent precision loss and zero transfer exploits ([f0e86e4](https://github.com/golemfoundation/octant-v2-core/commit/f0e86e4ad0766a0593bc82caeaa0846b02c71755))
* **allowance:** rebase issues about data types ([d4a21d8](https://github.com/golemfoundation/octant-v2-core/commit/d4a21d8ece020f474411cde77b7224223c339d77))
* **allowance:** struct packing and drip rate ceiling ([dc7be4c](https://github.com/golemfoundation/octant-v2-core/commit/dc7be4ce1e35a5c79e511a62cdcf47fa93700ca7))
* **test:** cast to correct type ([fd3caf9](https://github.com/golemfoundation/octant-v2-core/commit/fd3caf925b98a0fafe0712efe616f35ae89865bd))

## [0.3.0-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.2.5-develop.0...v0.3.0-develop.0) (2025-06-11)


### Features

* add payee naming and on-chain splitter lookup ([10df4ff](https://github.com/golemfoundation/octant-v2-core/commit/10df4ff925a5b6ce1770e3c141107ba1a840accd))
* add payee naming and on-chain splitter tracking ([52c3fb6](https://github.com/golemfoundation/octant-v2-core/commit/52c3fb64c75d75d0536f6d1e549a5ff4ecd405ab))
* **core:** add quadratic funding impact strategy ([0b0b354](https://github.com/golemfoundation/octant-v2-core/commit/0b0b3549fa40385355e948e70971be3adb8eb3f3))
* create DeployPaymentSplitter ([b412cc1](https://github.com/golemfoundation/octant-v2-core/commit/b412cc1bc99535f315400f836b36a682ed5d0da8))
* create DeployPaymentSplitterFactory ([7fcd6e6](https://github.com/golemfoundation/octant-v2-core/commit/7fcd6e6002d1ad14a7cc9ec18ee7d91c8734bb6a))
* create ILockedVault interface ([1c625d5](https://github.com/golemfoundation/octant-v2-core/commit/1c625d5732dbc6f6113d1ed33ef6762d5d4c2c71))
* create Lido strategy ([664bbe8](https://github.com/golemfoundation/octant-v2-core/commit/664bbe8ca2f34205d785962c498e570f1c240b2e))
* create LidoTest ([0cc47cd](https://github.com/golemfoundation/octant-v2-core/commit/0cc47cdf87c2f345a43a7b071860f3faf59d48d6))
* create LidoVaultFactory ([bb1db5d](https://github.com/golemfoundation/octant-v2-core/commit/bb1db5d2f2c0b4470412745b27fa839b4334977c))
* create MorphoCompounder ([fc3ed97](https://github.com/golemfoundation/octant-v2-core/commit/fc3ed97881c299eab0ef4ffc1bbbed7cb33807b1))
* create PaymentSplitterFactory ([b3ef3bb](https://github.com/golemfoundation/octant-v2-core/commit/b3ef3bb28804c98e00592babb2853f9c2f8e16e7))
* create Vault deployment script ([f68b6de](https://github.com/golemfoundation/octant-v2-core/commit/f68b6de7afc7e432b7d5c0d45d9e9a6e9c9c5e89))
* create VaultFactory ([5659cfb](https://github.com/golemfoundation/octant-v2-core/commit/5659cfbc0be643b904e38bc1bdd832bc48c599e0))
* create VaultFactory deployment script ([dbc1986](https://github.com/golemfoundation/octant-v2-core/commit/dbc19866a93129ca9d904bfe886d689aea53a7cb))
* create yield donating vault factory ([9501eee](https://github.com/golemfoundation/octant-v2-core/commit/9501eee5b14928b5a963cf9b3023a28bdce973f4))
* create YieldDonating MorphoCompounderStrategy ([413c6b0](https://github.com/golemfoundation/octant-v2-core/commit/413c6b01292e1c87c20bdec54c30d569a9a6fc0b))
* create YieldDonating MorphoCompounderStrategyVaultFactory ([ecb6294](https://github.com/golemfoundation/octant-v2-core/commit/ecb6294101280d25712156bc1caad83f2453b2e3))
* implement tokenized impact strategy with quadratic funding mechanism ([c4c816e](https://github.com/golemfoundation/octant-v2-core/commit/c4c816e97d0d2762f33973af461d614d8c3f5e55))
* initialize yearn v3 tokenized strategy contracts ([61af67b](https://github.com/golemfoundation/octant-v2-core/commit/61af67b82ad2c02e50b85118741f638f2a1907ea))
* **interfaces:** add smart contract interfaces for multiuser strategies ([3934cfd](https://github.com/golemfoundation/octant-v2-core/commit/3934cfd88388782fa75ee7d8b4498425b8413318))
* make grace period configurable ([d9b6b7c](https://github.com/golemfoundation/octant-v2-core/commit/d9b6b7c6dbcae74d26319823fa88dc86f0660979))
* make PaymentSplitter initializable ([27ec473](https://github.com/golemfoundation/octant-v2-core/commit/27ec473f7cf840a0d63e35fb72cf644b9fd0cbba))
* **mechanism:** add owner-only quorum updates and improve code formatting ([c296777](https://github.com/golemfoundation/octant-v2-core/commit/c296777112ff065643251dc9dfdb78c5a4a7efa3))
* **mechanism:** add start block parameter to QV mechanism ([09c0517](https://github.com/golemfoundation/octant-v2-core/commit/09c0517f68ef4f19187eb9cb8160e8244cbb077c))
* **mechanism:** add startBlock parameter to SimpleVotingMechanism ([0d7b205](https://github.com/golemfoundation/octant-v2-core/commit/0d7b205d3537d5b07733f0174f16362fc991f457))
* **mechanism:** implement quadratic voting allocation mechanism ([5d3a7e5](https://github.com/golemfoundation/octant-v2-core/commit/5d3a7e58bfb3dbbbfeafd51788e07fd1bae3ee6f))
* multi strategy vault ([b5d7dea](https://github.com/golemfoundation/octant-v2-core/commit/b5d7deab0d84a7071a98794377a7fa7ef8ffa8a9))
* **multiuser-strategy:** clean up new multiuser strategy base and lib contracts ([54acb54](https://github.com/golemfoundation/octant-v2-core/commit/54acb545b37ddb1dd30e8c6744c9748d418f3fb7))
* mvp LockedVault ([96fa7bc](https://github.com/golemfoundation/octant-v2-core/commit/96fa7bcaf04f9273230454e412791aac5afc9c20))
* pass tokenized strategy to constructor ([66bf06c](https://github.com/golemfoundation/octant-v2-core/commit/66bf06c9841b4c8b27c6c8ad8efe7ec59b80243e))
* **periphery:** import and adjust periphery contracts so we can use them with DragonTokenizedStrategy ([44328ea](https://github.com/golemfoundation/octant-v2-core/commit/44328eaf82796b21f85909c3fb0d74e8199e0650))
* **periphery:** import and adjust periphery contracts so we can use them with DragonTokenizedStrategy ([b6d56bd](https://github.com/golemfoundation/octant-v2-core/commit/b6d56bd169707a4b74099ce8d60f5195afdf6366))
* port PaymentSplitter ([39bf73e](https://github.com/golemfoundation/octant-v2-core/commit/39bf73e725bb51655e688bec032b670263a9fab0))
* **regen:** contribute function ([afdf9a5](https://github.com/golemfoundation/octant-v2-core/commit/afdf9a5df96aaf7897d650e0f7fa37d949728580))
* **regen:** new tests and refactorings ([44ddddd](https://github.com/golemfoundation/octant-v2-core/commit/44dddddd41fd4f697fac800ae78c28a6798de53e))
* **regen:** pausable withdraw and claimRewards ([c6f41d4](https://github.com/golemfoundation/octant-v2-core/commit/c6f41d4c8fa40283b6ac5307f6e9c367ff809393))
* **regen:** pause and tests ([3b59a0a](https://github.com/golemfoundation/octant-v2-core/commit/3b59a0a771fcf984d9d843ffdc1ba4c8cdd901bd))
* **regenstaker:** contribute with signature ([c62bebb](https://github.com/golemfoundation/octant-v2-core/commit/c62bebb0629588f773a41a68ace32ea82a16fc68))
* **regenstakerfactory:** implement with create3 ([3cf0cd8](https://github.com/golemfoundation/octant-v2-core/commit/3cf0cd82bcb82223887b9d2c46cacf2282ade637))
* **regenstakerfactory:** implement with create3 ([246a3ab](https://github.com/golemfoundation/octant-v2-core/commit/246a3abfd28186cc0233b9dd9d2e4dc203513797))
* **regenstaker:** toggleable minimum staking amount ([1ca1de4](https://github.com/golemfoundation/octant-v2-core/commit/1ca1de48c52c210a6d7e5222b9b4e221185ea087))
* **regenstaker:** variable reward duration, fixes, doc updates, and tests ([3dbd152](https://github.com/golemfoundation/octant-v2-core/commit/3dbd152b062d81b4e55a385f5f131828387349e2))
* **regen:** staking, license, whitelists and epc ([e7efcdf](https://github.com/golemfoundation/octant-v2-core/commit/e7efcdfb2a8273b56798b34275ad791fd67c9cc0))
* **regen:** staking, license, whitelists and epc ([3b840af](https://github.com/golemfoundation/octant-v2-core/commit/3b840afc568201c82df687d1e5757c0fa99e51d9))
* **strategy:** add yield skimming tokenized strategy implementation ([cd8ede6](https://github.com/golemfoundation/octant-v2-core/commit/cd8ede61094ba9c2fdc8aa348c389fe5edc9f645))
* **strategy:** implement yield donating tokenized strategy ([f455ce0](https://github.com/golemfoundation/octant-v2-core/commit/f455ce012c62cfb8bcac705e8d6d1852453a3205))
* **strategy:** implement YieldDonating strategy with tests and deployment ([9b5d49a](https://github.com/golemfoundation/octant-v2-core/commit/9b5d49a0d58a4ae1062597106c64e4694e92b943))
* **strategy:** multi user dragon tokenized strategy without profit locking, etc ([00cdf16](https://github.com/golemfoundation/octant-v2-core/commit/00cdf164bac1dbc760b611f3567a5d0938dafdbb))
* use mininal proxies for PaymentSplitterFactory ([5ce97fa](https://github.com/golemfoundation/octant-v2-core/commit/5ce97fa71f9626e9a5fb3dc31f37f5be4daa5c15))
* **voting:** add start block and restrict proposal cancellation ([b286392](https://github.com/golemfoundation/octant-v2-core/commit/b28639216953d2e63f68dfffc63ad261090d079d))
* **voting:** implement proper quadratic funding algorithm ([d7520c5](https://github.com/golemfoundation/octant-v2-core/commit/d7520c5ee8d50f592efc88ca609d4705ee85de8d))
* **yield-skimming:** dragon strategy variants for yield skimming variant ([030740b](https://github.com/golemfoundation/octant-v2-core/commit/030740b3bc5cea4cc7fd83faceb8bc5d6e9ea6dd))


### Bug Fixes

* align debt calculation with Vault.py ([0d924c6](https://github.com/golemfoundation/octant-v2-core/commit/0d924c68db4f2909d3042c7b1ba474ac1c9365c0))
* avoid reentrancy issue ([24b4ccc](https://github.com/golemfoundation/octant-v2-core/commit/24b4ccc95195c56820c09d7c8e512aa768c7e255))
* compiling issue in Vault ([b11d3b9](https://github.com/golemfoundation/octant-v2-core/commit/b11d3b9634b3b71fd80a5f474d9d949381f54199))
* **epc:** incorrect comparison between new and old earning power ([c6789ab](https://github.com/golemfoundation/octant-v2-core/commit/c6789abdade3de29ad62d5736a7a0dda7ce244fb))
* **factory:** add emergency admin to strategy constructor ([ac3efbb](https://github.com/golemfoundation/octant-v2-core/commit/ac3efbbebab9e0d5aff56ede649890a2d1014fae))
* initialize function in Vault ([3d6d7a0](https://github.com/golemfoundation/octant-v2-core/commit/3d6d7a04e2d19a6aa743de3e1d6a14e88c25610a))
* issues with roles bitmasks ([526575d](https://github.com/golemfoundation/octant-v2-core/commit/526575de479600ad2089e6e89b1c51f12bca6498))
* **regen:** prevent stake on behalf and permit and staked when paused ([9411e30](https://github.com/golemfoundation/octant-v2-core/commit/9411e30bdadd8120ea9c5b6d2eaaf4d5806744ba))
* **regen:** prevent stake on behalf and permit and staked when paused ([b87a76a](https://github.com/golemfoundation/octant-v2-core/commit/b87a76a2bb08f4af6664ac154cdf71c9600a2171))
* **regenstaker:** admin should be the owner of the all whitelisting contracts ([f217f9f](https://github.com/golemfoundation/octant-v2-core/commit/f217f9f7f460f82380001bec7beb8272cd8a0b23))
* **regenstaker:** admin should be the owner of the all whitelisting contracts ([081759f](https://github.com/golemfoundation/octant-v2-core/commit/081759ffa6e52634eff92c4077123b7b0f7ef6a2))
* **regenstakerfactory:** sal, event, natspec, tests ([12526bf](https://github.com/golemfoundation/octant-v2-core/commit/12526bf6eecb59df6d7197b9ea3878b0d7910dc3))
* **regenstaker:** prevent stake amount reaching below threshold through withdraw and contribute ([a41018c](https://github.com/golemfoundation/octant-v2-core/commit/a41018cd12a26dd9d21a025aa8024c7579440c07))
* **regenstaker:** prevent stake amount reaching below threshold through withdraw and contribute ([d6cf318](https://github.com/golemfoundation/octant-v2-core/commit/d6cf3187d0106d45e801e763cfb4b147ed06f85d))
* **regenstaker:** prevent stake amount reaching below threshold through withdraw and contribute ([bb8f57b](https://github.com/golemfoundation/octant-v2-core/commit/bb8f57b88a87696bba2c229d3cc305357c8db999))
* shadowed declarations in Vault.sol ([e5f1fb9](https://github.com/golemfoundation/octant-v2-core/commit/e5f1fb95ce28f21aa505531277ea116a9da78e9b))
* **strategy:** squash bugs and clean up integration to new base contracts ([60e495d](https://github.com/golemfoundation/octant-v2-core/commit/60e495d658d176a46ac3f71e8256354c0eca52ff))
* **strategy:** squash bugs and clean up integration to new base contracts ([28b41e4](https://github.com/golemfoundation/octant-v2-core/commit/28b41e4a440953f1d42cb789813b547c6887e39b))
* **test:** relax tolerance and bound minimum reward by Staker's limit ([d988257](https://github.com/golemfoundation/octant-v2-core/commit/d98825763ba92fc07eae5536540e13e6a7ac84e9))
* **test:** relax tolerance and bound minimum reward by Staker's limit ([cde1f1b](https://github.com/golemfoundation/octant-v2-core/commit/cde1f1b644f7d2ca22cb54f77cbd10ff329cbab2))
* **test:** relax tolerance and bound minimum reward by Staker's limit ([109073e](https://github.com/golemfoundation/octant-v2-core/commit/109073e07fffc9e820d5b3fb3d5367f8a4f57cc2))
* YieldSkimmingTokenizedStrategy dealing with totalAsset ([8eebac0](https://github.com/golemfoundation/octant-v2-core/commit/8eebac07fc51d1615782c2a603693a0aff30511c))

## [0.2.5-develop.0](https://github.com/golemfoundation/octant-v2-core/compare/v0.2.4-0...v0.2.5-develop.0) (2025-04-30)


### Bug Fixes

* add starting block to deployment logs and output file ([ba9631d](https://github.com/golemfoundation/octant-v2-core/commit/ba9631deacef50eb3b6dbeb793a39d1237b194c9))
* cache-array-length ([257aa32](https://github.com/golemfoundation/octant-v2-core/commit/257aa32dab873d81444de9aa4ec2eb75d8ac719f))
* divide-before-multiply ([b11dc40](https://github.com/golemfoundation/octant-v2-core/commit/b11dc40a42cb61e00b51383112a477074b4e16a3))
* ignore false positives ([07887dc](https://github.com/golemfoundation/octant-v2-core/commit/07887dcf50677ece59fcdd670ab2e59d948d1289))
* ignore unused-return ([793977c](https://github.com/golemfoundation/octant-v2-core/commit/793977c3e85009c8daf67dd0da153796dbbccaa5))
* incorrect-equality ([052b52c](https://github.com/golemfoundation/octant-v2-core/commit/052b52c70c7189d844cf57b3be05f560798370f1))
* pipeline token ([fa85fa9](https://github.com/golemfoundation/octant-v2-core/commit/fa85fa980d76e20aad2e85d77ee6f164713f9a0c))
* reentrancy-no-eth ([d6d2c36](https://github.com/golemfoundation/octant-v2-core/commit/d6d2c360e5ff76d88c2cbbdf899d2ae2284ef7e8))
* state-variables-that-could-be-declared-immutable ([492f9ad](https://github.com/golemfoundation/octant-v2-core/commit/492f9ad8e549537749f97a41ca2838c862b16874))
* uninitialized-local-variables ([893c82f](https://github.com/golemfoundation/octant-v2-core/commit/893c82fae62f6d11c0a4bc0b6335a6be1c07e849))
* var-read-using-this ([39142fe](https://github.com/golemfoundation/octant-v2-core/commit/39142fe9516970db657bb117e0620ca2d50f1f50))
