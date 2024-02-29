# Problems

## LZ

- blocking or nonblocking
- what if txn fails on dstChain: failure remedy, mitigation, automatic relies
- V1 vs/or V2
- which V2 lib/repo?
- postdeployment: monitoring dashboard where we can track metrics, health of system and so forth.

## Vault creation period

120 days from deployment vaults can be created.
lastDay = startDate + 120 days.
vault creation check: if vaultStart + duration exceed lastDay, reject creation
> rewards are emitted for 120 days

## Calculating rewards and fees

(Rewards and fees accounting)
- need to track creator and NFT fees.
- creator and NFT fees may vary.
- how to track rewards to users and fees in a varying manner

## StakingPool Misc

- vaults must be updated via script before `latestPoolTimestamp > vault.endTime`.
- once poolTimestamp exceeds vault.endTime, the vault cannot be updated any more.
- 24 hours before all vaults ought to be updated, just in case txn fails or due to sheer quantity.

## BATCHING

how to batch?

# FOR CLARIFICATION

## AccessControls

Well, what is the internal process w/ wallet mgmt?

- owner or RBAC?
- https://blog.openzeppelin.com/admin-accounts-and-multisigs
- https://www.rareskills.io/post/openzeppelin-ownable2step
- https://coinsbench.com/how-to-safely-manage-smart-contract-ownership-cc6acbbfcc8f?gi=2ca3c9fd515c


Router
- Uniswap Router and the Compound Bulker.

restrict fns on stakingPoolL: onlyRouter
 - users must user router to publicly call

2. refactor testing to be modular?


realm points?
 - need ability to burn rp on creation?

## Off-chain

`if(latestPoolTimestamp > vault.endTime) return vault`

- need a script to updateVaults seconds before they end
- this is to update vaultIndex before the vault expires, as once the vault expires it cannot be updated.
- avoid rewards slippage

### AllocPoints

- Once a vault ends, its allocPoints is not automatically deducted from the poolAllocPoints
- Only when `unstake` is called, is vaultAllocPoints deducted and therefore poolAllocPoints
- Do we wanna call unstake() for everyone?


## Multiplier

- don't update multiplier on unstake?
- has no material impact on other vaults or allocPoints


## TODO

- gas-less txns. create some kind of blocker so that userA cannot call functions on userB, like stake,create, etc
- cos fns work on onBehalf
- nft tokenID tracking
- max limits on staking tokens
- max limits on staking nfts
- rp check on creation