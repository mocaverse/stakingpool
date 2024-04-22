## constructor

- rewards vault must be deployed before pool, to check if rewards were deposited
- pre-deployed contracts: registry, rea


## token_precision

- precision is aactaully 18
- but we doing 10 *18 one shot to save on repeatition
- what should we then call it?

## _updateVaultIndex

- review the bit on vault maturing, vaultIndex not updated, exiting early 

## staking nfts

- bonus incentive
- ensure vaultIndex cal correctly against userNftindex


## unstaking

- check tt allocpoints decremented in `unstake` does not clash with FINAL TXN deduction in `updateVaultIndex`


## EVENTS

- NftRewardsAccrued and StakingRewardsAccrued -> just collapse to RewardsAccrued for both types?


## Rewards vault

- check fn calls against the pool


## do i really need the require statements?
- vaultId 
- address 
- just chuck it to the front-end


## check if vault is empty before checking if user has assets
```
        if(vault.stakedNfts == 0) revert VaultHasZeroStakedTokens();
        if(vault.stakedTokens == 0) revert VaultHasZeroStakedNfts();
```
 necessary?


## can remove IREALMPOINTS from PoolAgain
- chuck in the router


## Should these be immutable?
    IERC20 public immutable STAKED_TOKEN;  
    IERC20 public immutable REWARD_TOKEN;
    IRewardsVault public immutable REWARDS_VAULT;
    IRegistry public immutable REGISTRY;

    address public router;

- in both poolAgain and routerAgain
- if we have to redploy 1, what others must be redeployed?

# ROUTER

- msg.sender in batching
- how to call consume for rp burn: owner
