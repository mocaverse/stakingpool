// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Errors} from './Errors.sol';
import {DataTypes} from './DataTypes.sol';

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable2Step, Ownable} from  "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

// interfaces
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRealmPoints} from "./interfaces/IRealmPoints.sol";
import {IRewardsVault} from "./interfaces/IRewardsVault.sol";

contract Pool is ERC20, Pausable, Ownable2Step { 
    using SafeERC20 for IERC20;


    IERC20 public immutable STAKED_TOKEN;  
    IERC20 public immutable REWARD_TOKEN;
    IRewardsVault public immutable REWARDS_VAULT;
    IRegistry public immutable REGISTRY;

    // router address 
    address public router;

    // token dp: 18 decimal places
    uint256 public constant TOKEN_PRECISION = 10 ** 18;                       
      
    // times
    uint256 public immutable startTime;           // start time
    uint256 public endTime;                       // non-immutable: allow modification of staking period

    // pool emergency state
    bool public isFrozen;

    // pool data
    DataTypes.PoolAccounting public pool;


// ------- [note: need to confirm values] -------------------

    // vault multipliers: applied onto token values
    uint256 public constant VAULT_30D_MULTIPLIER = 100;     // 1.0x
    uint256 public constant VAULT_60D_MULTIPLIER = 125;     // 1.25x
    uint256 public constant VAULT_90D_MULTIPLIER = 150;     // 1.5x   

    // nft 
    uint256 public constant MAX_NFTS_PER_VAULT = 2; 
    uint256 public constant NFT_MULTIPLIER = 250;           // 2.5x multiplier 

    // token
    uint256 public constant BASE_MOCA_STAKING_LIMIT = 200_000 ether;     // on vault creation, starting value
    uint256 public constant MAX_MOCA_PER_VAULT = 1_000_000 ether;        // note: placeholder value
 
//-------------------------------mappings-------------------------------------------

    // user can own one or more Vaults, each one with a bytes32 identifier
    mapping(bytes32 vaultId => DataTypes.Vault vault) public vaults;              
                   
    // Tracks unclaimed rewards accrued for each user: user -> vaultId -> userInfo
    mapping(address user => mapping (bytes32 vaultId => DataTypes.UserInfo userInfo)) public users;

//-------------------------------constructor-------------------------------------------

    constructor(
        IERC20 stakedToken, IERC20 rewardToken, address rewardsVault, 
        address registry, address realmPoints, 
        uint256 startTime_, uint256 duration, uint256 rewards,
        string memory name, string memory symbol, address owner) payable Ownable(owner) ERC20(name, symbol) {
    
        // sanity check input data: time, period, rewards
        require(startTime_ > block.timestamp, "Invalid startTime");
          require(duration > 0, "Invalid period");
           require(rewards > 0, "Invalid rewards");

        // token assignments
        STAKED_TOKEN = stakedToken;
        REWARD_TOKEN = rewardToken;
        
        // interfaces: supporting contracts
        REGISTRY = IRegistry(registry);                  // nft
        REALM_POINTS = IRealmPoints(realmPoints);         // rp
        REWARDS_VAULT = IRewardsVault(rewardsVault);    

        // instantiate data
        DataTypes.PoolAccounting memory pool_;

        // set timing and duration
        startTime = pool_.poolLastUpdateTimeStamp = startTime_;
        endTime = startTime_ + duration;   
        
        // sanity check: eps calculation
        pool_.emissisonPerSecond = rewards / duration;
        require(pool_.emissisonPerSecond > 0, "emissisonPerSecond = 0");

        // sanity check: rewards vault has sufficient tokens
        require(rewards <= REWARDS_VAULT.totalVaultRewards(), "Insufficient vault rewards");
        pool_.totalStakingRewards = rewards;

        // update storage
        pool = pool_;

        emit DistributionUpdated(pool_.emissisonPerSecond, endTime);
    }

//-------------------------------external-------------------------------------------


    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    ///@dev creates empty vault
    function createVault(address onBehalfOf, DataTypes.VaultDuration duration, uint256 creatorFeeFactor, uint256 nftFeeFactor) external whenStarted whenNotPaused auth {

        // invalid vault type
        if(uint8(duration) == 0) revert Errors.InvalidVaultPeriod();      
        
        // period check
        uint256 vaultEndTime = block.timestamp + (30 days * uint8(duration));           //duration: 30,60,90
        if (endTime <= vaultEndTime) revert Errors.InsufficientTimeLeft();

        //note: total fee cannot exceed 100%, which is defined as 1e18 = TOKEN_PRECISION
        // individual feeFactors can be 0
        if((nftFeeFactor + creatorFeeFactor) > TOKEN_PRECISION) revert Errors.TotalFeeFactorExceeded();

        // vaultId generation
        bytes32 vaultId;
        {
            uint256 salt = block.number - 1;
            vaultId = _generateVaultId(salt, onBehalfOf);
            while (vaults[vaultId].vaultId != bytes32(0)) vaultId = _generateVaultId(--salt, onBehalfOf);      // If vaultId exists, generate new random Id
        }


        // update poolIndex: book prior rewards, based on prior alloc points 
        (DataTypes.PoolAccounting memory pool_, ) = _updatePoolIndex();

        // build vault
        DataTypes.Vault memory vault; 
            vault.vaultId = vaultId;
            vault.creator = onBehalfOf;
            vault.duration = duration;
            vault.endTime = vaultEndTime; 
            vault.multiplier = uint8(duration) == 3 ? VAULT_90D_MULTIPLIER : (uint8(duration) == 2 ? VAULT_60D_MULTIPLIER : VAULT_30D_MULTIPLIER);
            vault.stakedTokensLimit = BASE_MOCA_STAKING_LIMIT;                   //note: placeholder
            
            // index
            vault.accounting.vaultIndex = pool_.index;
            vault.accounting.nftFeeFactor = nftFeeFactor;
            vault.accounting.creatorFeeFactor = creatorFeeFactor;

        // update storage
        pool = pool_;
        vaults[vaultId] = vault;
        
        emit VaultCreated(onBehalfOf, vaultId, vaultEndTime, duration); //emit totaLAllocPpoints updated?
    }  


    function stakeTokens(bytes32 vaultId, address onBehalfOf, uint256 amount) external whenStarted whenNotPaused auth {
        require(amount > 0, "Invalid amount");
        require(vaultId > 0, "Invalid vaultId");

        // check if vault exists + cache user & vault structs to memory
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update all indexes and book all prior rewards
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // if vault matured or staking limit exceeded, revert
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if((vault.stakedTokens + amount) > MAX_MOCA_PER_VAULT) revert Errors.StakedTokenLimitExceeded(vaultId, vault.stakedTokens);

        // calc. allocPoints
        uint256 incomingAllocPoints = (amount * vault.multiplier);

        // increment allocPoints
        vault.allocPoints += incomingAllocPoints;
        pool.totalAllocPoints += incomingAllocPoints;
        
        // increment stakedTokens: user, vault
        vault.stakedTokens += amount;
        userInfo.stakedTokens += amount;

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // mint stkMOCA
        _mint(onBehalfOf, amount);

        emit StakedMoca(onBehalfOf, vaultId, amount);

        // grab MOCA
        STAKED_TOKEN.safeTransferFrom(onBehalfOf, address(this), amount);
    }


    // Note: reset NFT assoc via recordUnstake()
    // else users cannot switch nfts to the new pool.
    function stakeNfts(bytes32 vaultId, address onBehalfOf, uint256[] calldata tokenIds) external whenStarted whenNotPaused auth {
        uint256 incomingNfts = tokenIds.length;

        require(incomingNfts > 0 && incomingNfts < MAX_NFTS_PER_VAULT, "Invalid amount"); 
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // sanity checks: no staking if vault matured | nft staked amount cannot exceed limit
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);            
        if(vault.stakedNfts + incomingNfts > MAX_NFTS_PER_VAULT) revert Errors.NftStakingLimitExceeded(vaultId, vault.stakedNfts);
        
        // update user tokenIds
        userInfo.tokenIds = _concatArrays(userInfo.tokenIds, tokenIds);

        // update nft + multiplier
        vault.stakedNfts += incomingNfts;
        vault.multiplier += incomingNfts * NFT_MULTIPLIER;

        // cache
        uint256 oldMultiplier = vault.multiplier;
        uint256 oldAllocPoints = vault.allocPoints;

        // calc. new alloc points | there is only impact if vault has prior stakedTokens
        if(vault.stakedTokens > 0) {
            uint256 deltaAllocPoints = (vault.stakedTokens * vault.multiplier) - oldAllocPoints;

            // book 1st stake incentive | if no prior stake, no nft incentive
            if(vault.stakedNfts == 0) {
                userInfo.accNftStakingRewards = vault.accounting.accNftStakingRewards;
                emit NftRewardsAccrued(onBehalfOf, userInfo.accNftStakingRewards);
            }

            // update allocPoints
            vault.allocPoints += deltaAllocPoints;
            pool.totalAllocPoints += deltaAllocPoints;
        }
        
        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        emit StakedMocaNft(onBehalfOf, vaultId, tokenIds);
        emit VaultMultiplierUpdated(vaultId, oldMultiplier, vault.multiplier);

        // record stake with registry
        REGISTRY.recordStake(onBehalfOf, tokenIds, vaultId);
    }

    function claimRewards(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // update balances
        uint256 unclaimedRewards = userInfo.accStakingRewards - userInfo.claimedStakingRewards;
        userInfo.claimedStakingRewards += unclaimedRewards;
        vault.accounting.totalClaimedRewards += unclaimedRewards;

        //update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        emit RewardsClaimed(vaultId, onBehalfOf, unclaimedRewards);

        // transfer rewards to user, from rewardsVault
        REWARDS_VAULT.payRewards(onBehalfOf, unclaimedRewards);
    }

    function claimFees(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        uint256 totalUnclaimedRewards;

        // collect creator fees
        if(vault.creator == onBehalfOf) {
            uint256 unclaimedCreatorRewards = (vault.accounting.accCreatorRewards - userInfo.claimedCreatorRewards);
            
            if(unclaimedCreatorRewards > 0){
                totalUnclaimedRewards += unclaimedCreatorRewards;

                // update user balances
                userInfo.claimedCreatorRewards += unclaimedCreatorRewards;          
                emit CreatorRewardsClaimed(vaultId, onBehalfOf, unclaimedCreatorRewards);
            }
        }
        
        // collect NFT fees
        if(userInfo.accNftStakingRewards > 0) {    
            uint256 unclaimedNftRewards = (userInfo.accNftStakingRewards - userInfo.claimedNftRewards);
            
            if(unclaimedNftRewards > 0){
                totalUnclaimedRewards += unclaimedNftRewards;
                
                // update user balances
                userInfo.claimedNftRewards += unclaimedNftRewards;
                emit NftRewardsClaimed(vaultId, onBehalfOf, unclaimedNftRewards);
            }
        }
        
        // update vault balances
        vault.accounting.totalClaimedRewards += totalUnclaimedRewards;

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // transfer rewards to user, from rewardsVault
        REWARDS_VAULT.payRewards(onBehalfOf, totalUnclaimedRewards);
    } 

    function unstakeAll(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // get user holdings
        uint256 stakedNfts = userInfo.tokenIds.length;
        uint256 stakedTokens = userInfo.stakedTokens;

        // check if vault has matured + user has non-zero holdings
        if(block.timestamp < vault.endTime) revert Errors.VaultNotMatured(vaultId);
        if(stakedTokens == 0 && stakedNfts == 0) revert Errors.UserHasNothingStaked(vaultId, onBehalfOf); 

        //note: reset multiplier? or leave it for record keeping?
        // vault.multiplier = 1;

        //update balances: user + vault
        if(stakedNfts > 0){
            
            // record unstake with registry
            REGISTRY.recordUnstake(onBehalfOf, userInfo.tokenIds, vaultId);
            emit UnstakedMocaNft(onBehalfOf, vaultId, userInfo.tokenIds);       

            // update vault and user
            vault.stakedNfts -= stakedNfts;
            delete userInfo.tokenIds;
        }

        if(stakedTokens > 0){
            // update stakedTokens
            vault.stakedTokens -= userInfo.stakedTokens;
            delete userInfo.stakedTokens;
            
            // burn stkMOCA
            _burn(onBehalfOf, stakedTokens);
            emit UnstakedMoca(onBehalfOf, vaultId, stakedTokens);       
        }

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // return principal MOCA
        if(stakedTokens > 0) STAKED_TOKEN.safeTransfer(onBehalfOf, stakedTokens); 
    }

    // increase limit by the amount param. 
    // vault staking limit cannot exceed global hard cap
    // RP required = 50 + X. X goes towards calc. staking increment. 50 is a base charge.
    function increaseVaultLimit(bytes32 vaultId, address onBehalfOf, uint256 amount) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");
        
        // get vault + check if has been created
        (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);
        
        // check vault: not ended + user must be creator + global max not exceeded
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if(vault.creator != onBehalfOf) revert Errors.UserIsNotVaultCreator(vaultId, onBehalfOf);
    
        // increment limit 
        uint256 oldStakingLimit = vault.stakedTokensLimit;
        vault.stakedTokensLimit = amount + oldStakingLimit;

        // check that global hardcap is not exceeded
        if((vault.stakedTokensLimit) > MAX_MOCA_PER_VAULT) revert Errors.StakedTokenLimitExceeded(vaultId, vault.stakedTokens);

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        emit VaultStakingLimitIncreased(vaultId, oldStakingLimit, vault.stakedTokensLimit);
    }

    ///@notice Only allowed to reduce the creator fee factor
    function updateCreatorFee(bytes32 vaultId, address onBehalfOf, uint256 newCreatorFeeFactor) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");
        
        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // check vault: not ended + user must be creator 
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if(vault.creator != onBehalfOf) revert Errors.UserIsNotVaultCreator(vaultId, onBehalfOf);
        
        // incoming feeFactor must be lower than current
        if(newCreatorFeeFactor >= vault.accounting.creatorFeeFactor) revert Errors.CreatorFeeCanOnlyBeDecreased(vaultId);

        emit CreatorFeeFactorUpdated(vaultId, vault.accounting.creatorFeeFactor, newCreatorFeeFactor);

        // update Fee factor
        vault.accounting.creatorFeeFactor = newCreatorFeeFactor;
        
        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;
    }

    ///@notice Only allowed to increase the nft fee factor
    ///@dev Creator decrements the totalNftFeeFactor, which is dividied up btw the various nft stakers
    function updateNftFee(bytes32 vaultId, address onBehalfOf, uint256 newNftFeeFactor) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // check vault: not ended + user must be creator 
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if(vault.creator != onBehalfOf) revert Errors.UserIsNotVaultCreator(vaultId, onBehalfOf);
        
        // incoming NftFeeFactor must be more than current
        if(newNftFeeFactor <= vault.accounting.totalNftFeeFactor) revert Errors.NftFeeCanOnlyBeIncreased(vaultId);

        //note: total fee cannot exceed 100%, which is defined as 1e18 = TOKEN_PRECISION
        uint256 totalFeeFactor = newNftFeeFactor + vault.accounting.creatorFeeFactor;
        if(totalFeeFactor > TOKEN_PRECISION) revert Errors.TotalFeeFactorExceeded();

        emit NftFeeFactorUpdated(vaultId, vault.accounting.totalNftFeeFactor, newNftFeeFactor);
        
        // update Fee factor
        vault.accounting.totalNftFeeFactor = newNftFeeFactor;

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;
    }

    ///@dev to prevent index drift. Called by off-chain script
    ///@dev no need to restrict access since only an update occurs
    ///@note array length on gas
    function updateVault(bytes32[] calldata vaultIds) external whenStarted whenNotPaused {
        uint256 length = vaultIds.length;

        for(uint256 i = 0; i < length; ++i) {

            bytes32 vaultId = vaultIds[i];

            DataTypes.Vault memory vault = vaults[vaultId];
            DataTypes.Vault memory vault_ = _updateVaultIndex(vault);

            // update storage
            vaults[vaultId] = vault_;
        }               
    }

//-------------------------------internal-------------------------------------------

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Check if pool index is in need of updating, to bring it in-line with present time
     * @return poolAccounting struct, 
               currentTimestamp: either lasUpdateTimestamp or block.timestamp
     */
    function _updatePoolIndex() internal returns (DataTypes.PoolAccounting memory, uint256) {
        // cache
        DataTypes.PoolAccounting memory pool_ = pool;
        
        // already updated: return
        if(block.timestamp == pool_.poolLastUpdateTimeStamp) {
            return (pool_, pool_.poolLastUpdateTimeStamp);
        }
        
        // totalBalance = totalAllocPoints (boosted balances)
        (uint256 nextPoolIndex, uint256 currentTimestamp, uint256 emittedRewards) = _calculatePoolIndex(pool_.index, pool_.emissisonPerSecond, pool_.lastUpdateTimeStamp, pool.totalAllocPoints);

        if(nextPoolIndex != pool_.poolIndex) {
            
            // prev timestamp, oldIndex, newIndex: emit prev timestamp since you know the currentTimestamp as per txn time
            emit PoolIndexUpdated(pool_.lastUpdateTimeStamp, pool_.index, nextPoolIndex);

            pool_.index = nextPoolIndex;
            pool_.rewardsEmitted += emittedRewards; 
            pool_.poolLastUpdateTimeStamp = block.timestamp;
        }

        // update storage
        pool = pool_;

        return (pool_, currentTimestamp);
    }


    /**
     * @dev Calculates latest pool index. Pool index represents accRewardsPerAllocPoint since startTime.
     * @param currentPoolIndex Latest pool index as per previous update
     * @param emissionPerSecond Reward tokens emitted per second (in wei)
     * @param lastUpdateTimestamp Time at which previous update occured
     * @param totalBalance Total allocPoints of the pool 
     * @return nextPoolIndex: Updated pool index, 
               currentTimestamp: either lasUpdateTimestamp or block.timestamp, 
               emittedRewards: rewards emitted from lastUpdateTimestamp till now
     */
    function _calculatePoolIndex(uint256 currentPoolIndex, uint256 emissionPerSecond, uint256 lastUpdateTimestamp, uint256 totalBalance) internal view returns (uint256, uint256, uint256) {
        if (
            emissionPerSecond == 0                           // 0 emissions. no rewards setup. 
            || totalBalance == 0                             // nothing has been staked
            || lastUpdateTimestamp == block.timestamp        // assetIndex already updated
            || lastUpdateTimestamp > endTime                 // distribution has ended
        ) {

            return (currentPoolIndex, lastUpdateTimestamp, 0);                       
        }

        uint256 currentTimestamp = block.timestamp > endTime ? endTime : block.timestamp;
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        
        uint256 emittedRewards = emissionPerSecond * timeDelta;

        uint256 nextPoolIndex = ((emittedRewards * TOKEN_PRECISION) / totalBalance) + currentPoolIndex;
    
        return (nextPoolIndex, currentTimestamp, emittedRewards);
    }

    ///@dev called prior to affecting any state change to a vault
    ///@dev book prior rewards, update vaultIndex + totalAccRewards
    ///@dev does not update vault storage
    function _updateVaultIndex(DataTypes.Vault memory vault) internal returns(DataTypes.Vault memory) {
        //1. called on vault state-change: stake, claimRewards, etc
        //2. book prior rewards, before affecting state change
        //3. vaulIndex = newPoolIndex

        // get latest poolIndex
        (DataTypes.PoolAccounting memory pool_, uint256 latestPoolTimestamp) = _updatePoolIndex();

        // vault already been updated by a prior txn; exit early
        if(pool_.poolIndex == vault.accounting.vaultIndex) return vault;

        // If vault has matured, vaultIndex should not be updated, beyond the final update.
        // vault.allocPoints == 0, indicates that vault has matured and the final update has been done
        // no further updates should be made; exit early
        if(vault.allocPoints == 0) return vault;

        // update vault rewards + fees
        uint256 accruedRewards; 
        uint256 accCreatorFee; 
        uint256 accTotalNftFee;
        if (vault.stakedTokens > 0) {       // a vault can only accrue rewards when there are tokens staked

            // calc. prior unbooked rewards 
            accruedRewards = _calculateRewards(vault.allocPoints, pool_.poolIndex, vault.accounting.vaultIndex);

            // calc. fees: nft fees accrued even if no nft staked; given out to 1st nft staker
            if(vault.accounting.creatorFeeFactor > 0) {
                accCreatorFee = (accruedRewards * vault.accounting.creatorFeeFactor) / TOKEN_PRECISION;
            }
            if(vault.accounting.nftFeeFactor > 0) {
                accTotalNftFee = (accruedRewards * vault.accounting.nftFeeFactor) / TOKEN_PRECISION;  
            }

            // book rewards: total, creator, NFT
            vault.accounting.totalAccRewards += accruedRewards;
            vault.accounting.accCreatorRewards += accCreatorFee;
            vault.accounting.accNftStakingRewards += accTotalNftFee;

            // reference for users' to calc. rewards: rewards nett of fees
            vault.accounting.rewardsAccPerToken += ((accruedRewards - accCreatorFee - accTotalNFTFee) * TOKEN_PRECISION) / vault.stakedTokens;

            // nftIndex: rewardsAccPerNFT
            if(vault.stakedNfts > 0) {
                vault.accounting.vaultNftIndex += (accTotalNftFee / vault.stakedNfts);
            }
        }

        // update vaultIndex
        vault.accounting.vaultIndex = pool_.poolIndex;

        // note: FINAL UPDATE. pool and vault allocPoints decremented on maturity
        // use of >= as we cannot be sure that a txn will hit exactly at vault.endTime precisely
        // may result in some drift, and therefore reward dilution; considered to be acceptable
        if(latestPoolTimestamp >= vault.endTime) {
            if(vault.allocPoints > 0) {             //note: probably can drop token > 0 check, since vault returns on 0 allocPoints, earlier
                // decrement
                pool.totalAllocPoints -= vault.allocPoints;
                delete vault.allocPoints;
            }
        }   

        emit VaultIndexUpdated(vault.vaultId, vault.accounting.vaultIndex, vault.accounting.totalAccRewards);

        return vault;
    }

    ///@dev called prior to affecting any state change to a user
    ///@dev applies fees onto the vaulIndex to return the userIndex
    function _updateUserIndexes(address user, DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault_) internal returns (DataTypes.UserInfo memory, DataTypes.Vault memory) {

        // get latest vaultIndex + vaultNftIndex
        DataTypes.Vault memory vault = _updateVaultIndex(vault_);
        
        uint256 newUserIndex = vault.accounting.rewardsAccPerToken;
        uint256 newUserNftIndex = vault.accounting.vaultNftIndex;
        
        uint256 accruedRewards;
        if(userInfo.userIndex != newUserIndex) {
            if(userInfo.stakedTokens > 0) {
                
                // rewards from staking MOCA
                accruedRewards = _calculateRewards(userInfo.stakedTokens, newUserIndex, userInfo.userIndex);
                userInfo.accStakingRewards += accruedRewards;

                emit RewardsAccrued(user, accruedRewards);
            }
        }

        uint256 userStakedNfts = userInfo.tokenIds.length;
        if(userStakedNfts > 0) {
            if(userInfo.userNftIndex != newUserNftIndex){

                // total accrued rewards from staking NFTs
                uint256 accNftStakingRewards = (newUserNftIndex - userInfo.userNftIndex) * userStakedNfts;
                userInfo.accNftStakingRewards += accNftStakingRewards;
                emit NftRewardsAccrued(user, accNftStakingRewards);
            }
        }

        //update userIndex
        userInfo.userIndex = newUserIndex;
        userInfo.userNftIndex = newUserNftIndex;
        
        emit UserIndexesUpdated(user, vault.vaultId, newUserIndex, newUserNftIndex, userInfo.accStakingRewards);

        return (userInfo, vault);
    }

    function _calculateRewards(uint256 balance, uint256 currentIndex, uint256 priorIndex) internal pure returns (uint256) {
        return (balance * (currentIndex - priorIndex)) / TOKEN_PRECISION;
    }

    ///@dev cache vault and user structs from storage to memory. checks that vault exists, else reverts.
    function _cache(bytes32 vaultId, address onBehalfOf) internal view returns(DataTypes.UserInfo memory, DataTypes.Vault memory) {
        
        // ensure vault exists
        DataTypes.Vault memory vault = vaults[vaultId];
        if(vault.creator == address(0)) revert Errors.NonExistentVault(vaultId);

        // get userInfo for said vault
        DataTypes.UserInfo memory userInfo = users[onBehalfOf][vaultId];

        return (userInfo, vault);
    }

    ///@dev concat two uint256 arrays: [1,2,3],[4,5] -> [1,2,3,4,5]
    function _concatArrays(uint256[] memory arr1, uint256[] memory arr2) internal pure returns(uint256[] memory) {
        
        // create resulting arr
        uint256 len1 = arr1.length;
        uint256 len2 = arr2.length;
        uint256[] memory resArr = new uint256[](len1 + len2);
        
        uint256 i;
        for (; i < len1; i++) {
            resArr[i] = arr1[i];
        }
        
        uint256 j;
        while (j < len2) {
            resArr[i++] = arr2[j++];
        }

        return resArr;
    }

    ///@dev Generate a vaultId. keccak256 is cheaper than using a counter with a SSTORE, even accounting for eventual collision retries.
    function _generateVaultId(uint256 salt, address onBehalfOf) internal view returns (bytes32) {
        return bytes32(keccak256(abi.encode(onBehalfOf, block.timestamp, salt)));
    }

//-------------------------------pool management-------------------------------------------

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setRouter(address router_) external onlyOwner {
        require(router_ != address(0), "Invalid router");
        
        address oldRouter = router;
        router = router_;
        
        emit RouterUpdated(oldRouter, router_);
    }
    
    /**
     * @notice To increase the duration of staking period and/or the rewards emitted
     * @dev Can increase rewards, duration MAY be extended. cannot reduce.
     * @param amount Amount of tokens by which to increase rewards. Accepts 0 value.
     * @param duration Amount of seconds by which to increase duration. Accepts 0 value.
     */
    function updateEmission(uint256 amount, uint256 duration) external onlyOwner {
        // either amount or duration could be 0; but not both
        if(amount == 0 && duration == 0) revert Errors.InvalidEmissionParameters();

        // ensure staking has not ended
        uint256 endTime_ = endTime;
        require(block.timestamp < endTime_, "Staking ended");

        // close the books
        (DataTypes.PoolAccounting memory pool_, ) = _updatePoolIndex();

        // updated values: amount could be 0 
        uint256 unemittedRewards = pool_.totalPoolRewards - pool_.totalPoolRewardsEmitted;
        unemittedRewards += amount;
        require(unemittedRewards > 0, "Updated rewards: 0");
        
        // updated values: duration could be 0
        uint256 newDurationLeft = endTime_ + duration - block.timestamp;
        require(newDurationLeft > 0, "Updated duration: 0");
        
        // recalc: eps, endTime
        pool_.emissisonPerSecond = unemittedRewards / newDurationLeft;
        require(pool_.emissisonPerSecond > 0, "Updated EPS: 0");
        
        uint256 newEndTime = endTime_ + duration;

        // update storage
        pool = pool_;
        endTime = newEndTime;

        emit DistributionUpdated(pool_.emissisonPerSecond, newEndTime);
    }


    /**
     * @notice Pause pool
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause pool
     */
    function unpause() external onlyOwner {
        _unpause();
    }


    /**
     * @notice To freeze the pool in the event of something untoward occuring
     * @dev Only callable from a paused state, affirming that staking should not resume
     *      Nothing to be updated. Freeze as is.
            Enables emergencyExit() to be called.
     */
    function freeze() external whenPaused onlyOwner {
        require(isFrozen == false, "Pool is frozen");
        
        isFrozen = true;

        emit PoolFrozen(block.timestamp);
    }  


    /*//////////////////////////////////////////////////////////////
                                RECOVER
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice For users to recover their principal assets in a black swan event
     * @dev Rewards and fees are not withdrawn; indexes are not updated
     * @param vaultId Address of token contract
     * @param onBehalfOf Recepient of tokens
     */
    function emergencyExit(bytes32 vaultId, address onBehalfOf) external whenStarted whenPaused onlyOwner {
        require(isFrozen, "Pool not frozen");
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _cache(vaultId, onBehalfOf);

        // check user has non-zero holdings
        uint256 stakedNfts = userInfo.tokenIds.length;
        uint256 stakedTokens = userInfo.stakedTokens;       
        if(stakedNfts == 0 && stakedTokens == 0) revert Errors.UserHasNothingStaked(vaultId, onBehalfOf);
       
        // update balances: user + vault
        if(stakedNfts > 0){

            // record unstake with registry, else users cannot switch nfts to the new pool
            REGISTRY.recordUnstake(onBehalfOf, userInfo.tokenIds, vaultId);
            emit UnstakedMocaNft(onBehalfOf, vaultId, userInfo.tokenIds);       

            // update vault and user
            vault.stakedNfts -= stakedNfts;
            delete userInfo.tokenIds;
        }

        if(stakedTokens > 0){

            vault.stakedTokens -= stakedTokens;
            delete userInfo.stakedTokens;
            
            // burn stkMOCA
            _burn(onBehalfOf, stakedTokens);
            emit UnstakedMoca(onBehalfOf, vaultId, stakedTokens);       
        }

        /**
            Note:
            we do not zero out or decrement the following values: 
                1. vault.allocPoints 
                2. vault.multiplier
                3. pool.totalAllocPoints
            These values are retained to preserve state history at time of failure.
            This can serve as useful reference during post-mortem and potentially assist with any remediative actions.
         */

        // update storage 
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // return principal stake
        if(stakedTokens > 0) STAKED_TOKEN.safeTransfer(onBehalfOf, stakedTokens); 
    }


    /**  NOTE: Consider dropping to avoid admin abuse
     * @notice Recover random tokens accidentally sent to the vault
     * @param tokenAddress Address of token contract
     * @param receiver Recepient of tokens
     * @param amount Amount to retrieve
     */
    function recoverERC20(address tokenAddress, address receiver, uint256 amount) external onlyOwner {
        require(tokenAddress != address(STAKED_TOKEN), "StakedToken: Not allowed");
        require(tokenAddress != address(REWARD_TOKEN), "RewardToken: Not allowed");

        emit RecoveredTokens(tokenAddress, receiver, amount);

        IERC20(tokenAddress).safeTransfer(receiver, amount);
    }


    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/


    modifier whenStarted() {

        require(block.timestamp >= startTime, "Not started");    

        _;
    }


    modifier auth() {
        
        require(msg.sender == router || msg.sender == owner(), "Incorrect Caller");    

        _;
    }

}
