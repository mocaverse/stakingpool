// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from './Errors.sol';
import {DataTypes} from './DataTypes.sol';
import {RevertMsgExtractor} from "./utils/RevertMsgExtractor.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

//accesscontrol
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable2Step, Ownable} from  "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

// interfaces
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRewardsVault} from "./interfaces/IRewardsVault.sol";
import {IMocaPoints} from "./interfaces/IMocaPoints.sol";

//Note: inherit ERC20 to issue stkMOCA
contract Pool is ERC20, Pausable, Ownable2Step { 
    using SafeERC20 for IERC20;

    // rp contract interfaces, token interfaces,
    IMocaPoints public immutable REALM_POINTS;
    IRegistry public immutable REGISTRY;
    IERC20 public immutable STAKED_TOKEN;  
    
    IERC20 public immutable REWARD_TOKEN;
    IRewardsVault public immutable REWARDS_VAULT;

    // router address 
    address public router;

    // token dp
    uint256 public constant PRECISION = 18;                       
    
    // multipliers
    uint256 public constant nftMultiplier = 2;
    uint256 public constant vault60Multiplier = 2;
    uint256 public constant vault90Multiplier = 3;
  
    // timing
    uint256 public immutable startTime;           // start time
    uint256 public endTime;                       // non-immutable: allow extension staking period

    // state
    bool public isFrozen;

    // Pool Accounting
    DataTypes.PoolAccounting public pool;

// ------- [note: need to confirm values] -------------------

    // realm points 
    bytes32 public constant season = hex"01"; 
    bytes32 public constant consumeReasonCode = hex"01";

    //increments
    uint256 public constant MOCA_INCREMENT_PER_RP = 800 ether;    

    // staking limits
    uint256 public constant MAX_NFTS_PER_VAULT = 3; 
    uint256 public constant BASE_MOCA_STAKING_LIMIT = 200_000 ether;    // on vault creation, starting value
    uint256 public constant MAX_MOCA_PER_VAULT = 1_000_000 ether;        //note: placeholder value
 
//-------------------------------Events---------------------------------------------

    // EVENTS
    event DistributionUpdated(uint256 indexed newPoolEPS, uint256 indexed newEndTime);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    event PoolIndexUpdated(uint256 indexed lastUpdateTimestamp, uint256 indexed oldIndex, uint256 indexed newIndex);
    event VaultIndexUpdated(bytes32 indexed vaultId, uint256 indexed vaultIndex, uint256 indexed vaultAccruedRewards);
    event VaultMultiplierUpdated(bytes32 indexed vaultId, uint256 indexed oldMultiplier, uint256 indexed newMultiplier);

    event UserIndexUpdated(address indexed user, bytes32 indexed vaultId, uint256 userIndex, uint256 userAccruedRewards);

    event VaultCreated(address indexed creator, bytes32 indexed vaultId, uint256 indexed endTime, DataTypes.VaultDuration duration);
    
    event StakedMoca(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
    event StakedMocaNft(address indexed onBehalfOf, bytes32 indexed vaultId, uint256[] indexed tokenIds);
    event UnstakedMoca(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
    event UnstakedMocaNft(address indexed onBehalfOf, bytes32 indexed vaultId, uint256[] indexed tokenIds);

    event RewardsAccrued(address indexed user, uint256 amount);
    event NftFeesAccrued(address indexed user, uint256 amount);

    event RewardsClaimed(bytes32 indexed vaultId, address indexed user, uint256 amount);
    event NftRewardsClaimed(bytes32 indexed vaultId, address indexed creator, uint256 amount);
    event CreatorRewardsClaimed(bytes32 indexed vaultId, address indexed creator, uint256 amount);

    event CreatorFeeFactorUpdated(bytes32 indexed vaultId, uint256 indexed oldCreatorFeeFactor, uint256 indexed newCreatorFeeFactor);
    event NftFeeFactorUpdated(bytes32 indexed vaultId, uint256 indexed oldCreatorFeeFactor, uint256 indexed newCreatorFeeFactor);

    event RecoveredTokens(address indexed token, address indexed target, uint256 indexed amount);
    event PoolFrozen(uint256 indexed timestamp);

    event VaultStakingLimitIncreased(bytes32 indexed vaultId, uint256 oldStakingLimit, uint256 indexed newStakingLimit);

    event RealmPointsBurnt(uint256 realmId, uint256 rpBurnt);

//-------------------------------mappings-------------------------------------------

    // user can own one or more Vaults, each one with a bytes32 identifier
    mapping(bytes32 vaultId => DataTypes.Vault vault) public vaults;              
                   
    // Tracks unclaimed rewards accrued for each user: user -> vaultId -> userInfo
    mapping(address user => mapping (bytes32 vaultId => DataTypes.UserInfo userInfo)) public users;

//-------------------------------external-------------------------------------------


    constructor(
        IERC20 stakedToken, IERC20 rewardToken, address realmPoints, address rewardsVault, address registry, 
        uint256 startTime_, uint256 duration, uint256 rewards,
        string memory name, string memory symbol, address owner) payable Ownable(owner) ERC20(name, symbol) {
    
        // sanity check: duration
        require(startTime_ > block.timestamp && duration > 0, "Invalid period");
        require(rewards > 0, "Invalid rewards");

        STAKED_TOKEN = stakedToken;
        REWARD_TOKEN = rewardToken;

        REALM_POINTS = IMocaPoints(realmPoints);
        REWARDS_VAULT = IRewardsVault(rewardsVault);
        REGISTRY = IRegistry(registry);

        DataTypes.PoolAccounting memory pool_;

        // timing and duration
        startTime = pool_.poolLastUpdateTimeStamp = startTime_;
        endTime = startTime_ + duration;   
        
        // sanity checks: eps
        pool_.emissisonPerSecond = rewards / duration;
        require(pool_.emissisonPerSecond > 0, "reward rate = 0");

        // reward vault must hold necessary tokens
        pool_.totalPoolRewards = rewards;
        require(rewards <= REWARDS_VAULT.totalVaultRewards(), "reward amount > totalVaultRewards");

        // update storage
        pool = pool_;

        emit DistributionUpdated(pool_.emissisonPerSecond, endTime);
    }


    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    ///@dev create empty vault, without need for RP
    function createFreeVault() external whenStarted whenNotPaused onlyOwner {}

    ///@dev creates empty vault
    function createVault(address onBehalfOf, uint8 salt, DataTypes.VaultDuration duration, uint256 creatorFee, uint256 nftFee,  uint256 realmId, uint8 v, bytes32 r, bytes32 s) external whenStarted whenNotPaused auth {
        //note: placeholder. rp check + call consume
        uint256 rpRequired;
        _checkAndBurnRp(rpRequired, realmId, v, r, s);

        // invalid selection
        if(uint8(duration) == 0) revert Errors.InvalidVaultPeriod();      
        
        // period check
        uint256 vaultEndTime = block.timestamp + (30 days * uint8(duration));           //duration: 30,60,90
        if (endTime <= vaultEndTime) revert Errors.InsufficientTimeLeft();

        // vaultId generation
        bytes32 vaultId = _generateVaultId(salt);
        while (vaults[vaultId].vaultId != bytes32(0)) vaultId = _generateVaultId(++salt);      // If vaultId exists, generate new random Id

        // update poolIndex: book prior rewards, based on prior alloc points 
        (DataTypes.PoolAccounting memory pool_, ) = _updatePoolIndex();

        // build vault
        DataTypes.Vault memory vault; 
            vault.vaultId = vaultId;
            vault.creator = onBehalfOf;
            vault.duration = duration;
            vault.endTime = vaultEndTime; 
            vault.multiplier = uint8(duration); 
            vault.stakedTokensLimit = BASE_MOCA_STAKING_LIMIT;                   //note: placeholder
            
            // index
            vault.accounting.vaultIndex = pool_.poolIndex;
            // fees: note: precision check + 100% check
            vault.accounting.totalNftFeeFactor = nftFee;
            vault.accounting.creatorFeeFactor = creatorFee;

        // update storage
        pool = pool_;
        vaults[vaultId] = vault;
        
        emit VaultCreated(onBehalfOf, vaultId, vaultEndTime, duration); //emit totaLAllocPpoints updated?
    }  

    function stakeTokens(bytes32 vaultId, address onBehalfOf, uint256 amount) external whenStarted whenNotPaused auth {
        // usual blah blah checks
        require(amount > 0, "Invalid amount");
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
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
        uint256 arrLength = tokenIds.length;

        // usual blah blah checks
        require(arrLength > 0 && arrLength < MAX_NFTS_PER_VAULT, "Invalid amount"); 
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // sanity checks: if vault matured, no staking | new nft staked amount cannot exceed limit
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);            
        if(vault.stakedNfts + arrLength > MAX_NFTS_PER_VAULT) revert Errors.NftStakingLimitExceeded(vaultId, vault.stakedNfts);

        // update user & book 1st stake incentive
        userInfo.stakedNfts += arrLength;
        userInfo.tokenIds = _concatArrays(userInfo.tokenIds, tokenIds);
        if(vault.stakedNfts == 0) {
            userInfo.accNftStakingRewards = vault.accounting.accNftStakingRewards;
            emit NftFeesAccrued(onBehalfOf, userInfo.accNftStakingRewards);
        }

        // calc. delta
        uint256 oldMultiplier = vault.multiplier;
        uint256 oldAllocPoints = vault.allocPoints;
        
        // update vault
        vault.stakedNfts += arrLength;
        vault.multiplier += arrLength * nftMultiplier;

        //calc. new alloc points | there is only impact if vault has prior stakedTokens
        if(vault.stakedTokens > 0) {
            uint256 newAllocPoints = vault.stakedTokens * vault.multiplier;
            uint256 deltaAllocPoints = newAllocPoints - oldAllocPoints;
            
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
        // usual blah blah checks
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // update balances
        uint256 totalUnclaimedRewards = userInfo.accStakingRewards - userInfo.claimedStakingRewards;
        userInfo.claimedStakingRewards += totalUnclaimedRewards;
        vault.accounting.totalClaimedRewards += totalUnclaimedRewards;

        //update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        emit RewardsClaimed(vaultId, onBehalfOf, totalUnclaimedRewards);

        // transfer rewards to user, from rewardsVault
        REWARDS_VAULT.payRewards(onBehalfOf, totalUnclaimedRewards);
    }

    function claimFees(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused auth {
        // usual blah blah checks
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        uint256 totalUnclaimedRewards;

        // collect creator fees
        if(vault.creator == onBehalfOf) {
            uint256 unclaimedCreatorRewards = (vault.accounting.accCreatorRewards - userInfo.claimedCreatorRewards);
            totalUnclaimedRewards += unclaimedCreatorRewards;

            // update user balances
            userInfo.claimedCreatorRewards += unclaimedCreatorRewards;          

            emit CreatorRewardsClaimed(vaultId, onBehalfOf, unclaimedCreatorRewards);
        }
        
        // collect NFT fees
        if(userInfo.accNftStakingRewards > 0){    
            uint256 unclaimedNftRewards = (userInfo.accNftStakingRewards - userInfo.claimedNftRewards);
            totalUnclaimedRewards += unclaimedNftRewards;
            
            // update user balances
            userInfo.claimedNftRewards += unclaimedNftRewards;
         
            emit NftRewardsClaimed(vaultId, onBehalfOf, unclaimedNftRewards);
        }
        
        // update vault balances
        vault.accounting.totalClaimedRewards += totalUnclaimedRewards;

        //update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // transfer rewards to user, from rewardsVault
        REWARDS_VAULT.payRewards(onBehalfOf, totalUnclaimedRewards);
    } 

    function unstakeAll(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused auth {
        // usual blah blah checks
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // check if vault has matured
        if(block.timestamp < vault_.endTime) revert Errors.VaultNotMatured(vaultId);
        if(userInfo_.stakedTokens == 0 && userInfo_.stakedNfts == 0) revert Errors.UserHasNothingStaked(vaultId, onBehalfOf);

        // revert if 0 balances of tokens or nfts?
        // if(userInfo_.stakedNfts < 0 || userInfo_.stakedTokens) revert 

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        //get user balances
        uint256 stakedNfts = userInfo.stakedNfts;
        uint256 stakedTokens = userInfo.stakedTokens;

        // update allocPoints
        pool.totalAllocPoints -= vault.allocPoints;       // update storage: pool
        vault.allocPoints = 0;

        //note:  reset multiplier?
        // vault.multiplier = 1;

        //update balances: user + vault
        if(stakedNfts > 0){
            
            // record unstake with registry
            REGISTRY.recordUnstake(onBehalfOf, userInfo.tokenIds, vaultId);
            emit UnstakedMocaNft(onBehalfOf, vaultId, userInfo.tokenIds);       

            // update vault and user
            vault.stakedNfts -= userInfo.stakedNfts;
            delete userInfo.stakedNfts;
            delete userInfo.tokenIds;
        }

        if(stakedTokens > 0){
            // update stakedTokens
            vault.stakedTokens -= userInfo.stakedTokens;
            userInfo.stakedTokens = 0;
            
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
    function increaseVaultLimit(bytes32 vaultId, address onBehalfOf, uint256 amount,  uint256 realmId, uint8 v, bytes32 r, bytes32 s) external whenStarted whenNotPaused auth {
        require(vaultId > 0, "Invalid vaultId");
        require(amount > MOCA_INCREMENT_PER_RP, "Invalid increment");

        // calc. RP required. fee charge: 50 RP, every RP thereafter contributes to incrementing the limit
        // division involves rounding down
        uint256 rpRequired = (amount / MOCA_INCREMENT_PER_RP) + 50;
        _checkAndBurnRp(rpRequired, realmId, v, r, s);
        
        // get vault + check if has been created
        (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);
        
        // check vault: not ended + user must be creator + global max not exceeded
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if(vault.creator != onBehalfOf) revert Errors.UserIsNotVaultCreator(vaultId, onBehalfOf);
    
        // increment limit 
        uint256 oldStakingLimit = vault.stakedTokensLimit;
        vault.stakedTokensLimit = (rpRequired * MOCA_INCREMENT_PER_RP) + oldStakingLimit;

        // check that global hardcap is not exceeded
        if((vault.stakedTokensLimit) > MAX_MOCA_PER_VAULT) revert Errors.StakedTokenLimitExceeded(vaultId, vault.stakedTokens);

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        emit VaultStakingLimitIncreased(vaultId, oldStakingLimit, vault.stakedTokensLimit);
    }
    
    ///@notice Only allowed to reduce the creator fee factor
    function updateCreatorFee(bytes32 vaultId, address onBehalfOf, uint256 newCreatorFeeFactor,  uint256 realmId, uint8 v, bytes32 r, bytes32 s) external whenStarted whenNotPaused auth {
        
        //note: 50 RP needed to adjust fees
        _checkAndBurnRp(50, realmId, v, r, s);

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // check vault: not ended + user must be creator 
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if(vault.creator != onBehalfOf) revert Errors.UserIsNotVaultCreator(vaultId, onBehalfOf);
        
        // incoming feeFactor must be lower than current
        if(newCreatorFeeFactor >= vault.accounting.creatorFeeFactor) revert Errors.CreatorFeeCanOnlyBeDecreased(vaultId);

        //note: total fee cannot exceed 100%, which is defined as 1e18
        uint256 totalFeeFactor = newCreatorFeeFactor + vault.accounting.totalNftFeeFactor;
        if(totalFeeFactor > 1e18) revert Errors.TotalFeeFactorExceeded();

        emit CreatorFeeFactorUpdated(vaultId, vault.accounting.creatorFeeFactor, newCreatorFeeFactor);

        // update Fee factor
        vault.accounting.creatorFeeFactor = newCreatorFeeFactor;
        
        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;
    }

    ///@notice Only allowed to increase the nft fee factor
    ///@dev Creator decrements the totalNftFeeFactor, which is dividied up btw the various nft stakers
    function updateNftFee(bytes32 vaultId, address onBehalfOf, uint256 newNftFeeFactor,   uint256 realmId, uint8 v, bytes32 r, bytes32 s) external whenStarted whenNotPaused auth {
        
        //note: 50 RP needed to adjust fees
        _checkAndBurnRp(50, realmId, v, r, s);

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        // check vault: not ended + user must be creator 
        if(vault.endTime <= block.timestamp) revert Errors.VaultMatured(vaultId);
        if(vault.creator != onBehalfOf) revert Errors.UserIsNotVaultCreator(vaultId, onBehalfOf);
        
        // incoming NftFeeFactor must be more than current
        if(newNftFeeFactor <= vault.accounting.totalNftFeeFactor) revert Errors.NftFeeCanOnlyBeIncreased(vaultId);

        //note: total fee cannot exceed 100%, which is defined as 1e18
        uint256 totalFeeFactor = newNftFeeFactor + vault.accounting.creatorFeeFactor;
        if(totalFeeFactor > 1e18) revert Errors.TotalFeeFactorExceeded();

        emit NftFeeFactorUpdated(vaultId, vault.accounting.totalNftFeeFactor, newNftFeeFactor);
        
        // update Fee factor
        vault.accounting.totalNftFeeFactor = newNftFeeFactor;

        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;
    }


    ///@dev to prevent index drift. Called by off-chain script
    ///@dev no need to restrict access
    function updateVault(bytes32 vaultId) external whenStarted whenNotPaused {
        DataTypes.Vault memory vault = vaults[vaultId];
        DataTypes.Vault memory vault_ = _updateVaultIndex(vault);

        //update storage
        vaults[vaultId] = vault_;
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
        DataTypes.PoolAccounting memory pool_ = pool;
        
        if(block.timestamp == pool_.poolLastUpdateTimeStamp) {
            return (pool_, pool_.poolLastUpdateTimeStamp);
        }
        
        // totalBalance = totalAllocPoints (boosted balance)
        (uint256 nextPoolIndex, uint256 currentTimestamp, uint256 emittedRewards) = _calculatePoolIndex(pool_.poolIndex, pool_.emissisonPerSecond, pool_.poolLastUpdateTimeStamp, pool.totalAllocPoints);

        if(nextPoolIndex != pool_.poolIndex) {
            
            //stale timestamp, oldIndex, newIndex: emit staleTimestamp since you know the currentTimestamp upon emission
            emit PoolIndexUpdated(pool_.poolLastUpdateTimeStamp, pool_.poolIndex, nextPoolIndex);

            pool_.poolIndex = nextPoolIndex;
            pool_.totalPoolRewardsEmitted += emittedRewards; 
        }

        pool_.poolLastUpdateTimeStamp = block.timestamp;  //note: shouldn't this go into the if()?

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
            emissionPerSecond == 0                          // 0 emissions. no rewards setup.
            || totalBalance == 0                             // nothing has been staked
            || lastUpdateTimestamp == block.timestamp        // assetIndex already updated
            || lastUpdateTimestamp > endTime                 // distribution has ended
        ) {

            return (currentPoolIndex, lastUpdateTimestamp, 0);                       
        }

        uint256 currentTimestamp = block.timestamp > endTime ? endTime : block.timestamp;
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        
        uint256 emittedRewards = emissionPerSecond * timeDelta;

        uint256 nextPoolIndex = ((emittedRewards * 10 ** PRECISION) / totalBalance) + currentPoolIndex;
    
        return (nextPoolIndex, currentTimestamp, emittedRewards);
    }

    /**
     * @dev Calculates accrued rewards from prior index to current index. 
            Indexes are either rewardsAccPerToken or rewardsAccPerAllocPoint.
     * @param balance Specified as either tokenBalance or allocPoints 
     * @param currentIndex Latest index, reflective of current conditions
     * @param priorIndex Index as per the lastTimestamp or last instance it was updated
     */
    function _calculateRewards(uint256 balance, uint256 currentIndex, uint256 priorIndex) internal pure returns (uint256) {
        return (balance * (currentIndex - priorIndex)) / 10 ** PRECISION;
    }

    ///@dev called prior to affecting any state change to a vault
    ///@dev book prior rewards, update vaultIndex, totalAccRewards
    function _updateVaultIndex(DataTypes.Vault memory vault) internal returns(DataTypes.Vault memory) {
        //1. called on vault state-change: stake, claimRewards
        //2. book prior rewards, before affecting statechange
        //3. vaulIndex = newPoolIndex

        // get latest poolIndex
        (DataTypes.PoolAccounting memory pool_, uint256 latestPoolTimestamp) = _updatePoolIndex();

        // If vault has matured, vaultIndex should no longer be updated, (and therefore userIndex). 
        // IF vault has the same index as pool, the vault has already been updated to current time by a prior txn.
        if(latestPoolTimestamp > vault.endTime || pool_.poolIndex == vault.accounting.vaultIndex) return(vault);                                       

        uint256 accruedRewards;
        if (vault.stakedTokens > 0) {

            // calc. prior unbooked rewards 
            accruedRewards = _calculateRewards(vault.allocPoints, pool_.poolIndex, vault.accounting.vaultIndex);

            // calc. fees: nft fees accrued even if no nft staked. given out to 1st nft staker
            uint256 accCreatorFee = (accruedRewards * vault.accounting.creatorFeeFactor) / 10 ** PRECISION;
            uint256 accTotalNFTFee = (accruedRewards * vault.accounting.totalNftFeeFactor) / 10 ** PRECISION;  

            // book rewards: total, creator, NFT
            vault.accounting.totalAccRewards += accruedRewards;
            vault.accounting.accCreatorRewards += accCreatorFee;
            vault.accounting.accNftStakingRewards += accTotalNFTFee;

            // reference for users' to calc. rewards
            vault.accounting.rewardsAccPerToken += ((accruedRewards - accCreatorFee - accTotalNFTFee) * 10 ** PRECISION) / vault.stakedTokens;

            if(vault.stakedNfts > 0) {
                // rewardsAccPerNFT
                vault.accounting.vaultNftIndex += (accTotalNFTFee / vault.stakedNfts);
            }
        }

        // update vaultIndex
        vault.accounting.vaultIndex = pool_.poolIndex;

        emit VaultIndexUpdated(vault.vaultId, vault.accounting.vaultIndex, vault.accounting.totalAccRewards);

        return vault;

    }

    ///@dev called prior to affecting any state change to a user
    ///@dev applies fees onto the vaulIndex to return the userIndex
    function _updateUserIndexes(address user, DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault_) internal returns (DataTypes.UserInfo memory, DataTypes.Vault memory) {

        // get lastest vaultIndex + vaultNftIndex
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

        if(userInfo.stakedNfts > 0) {
            if(userInfo.userNftIndex != newUserNftIndex){

                // total accrued rewards from staking NFTs
                uint256 accNftStakingRewards = (newUserNftIndex - userInfo.userNftIndex) * userInfo.stakedNfts;
                userInfo.accNftStakingRewards += accNftStakingRewards;
                emit NftFeesAccrued(user, accNftStakingRewards);
            }
        }

        //update userIndex
        userInfo.userIndex = newUserIndex;
        userInfo.userNftIndex = newUserNftIndex;
        
        emit UserIndexUpdated(user, vault.vaultId, newUserIndex, userInfo.accStakingRewards);

        return (userInfo, vault);
    }
        
    ///@dev cache vault and user structs from storage to memory. checks that vault exists, else reverts.
    function _cache(bytes32 vaultId, address onBehalfOf) internal view returns(DataTypes.UserInfo memory, DataTypes.Vault memory) {
        
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
    function _generateVaultId(uint8 salt) internal view returns (bytes32) {
        return bytes32(keccak256(abi.encode(msg.sender, block.timestamp, salt)));
    }

    ///@dev Check a realmId's RP balance is sufficient; if so burn the required RP. Else revert
    function _checkAndBurnRp(uint256 rpRequired, uint256 realmId, uint8 v, bytes32 r, bytes32 s) internal {
        //note: rp check + burn + calc matching amount + revert if insufficient
        // balanceOf(bytes32 season, uint256 realmId) || realmPoints precision: expressed in integers 
        uint256 userRp = REALM_POINTS.balanceOf(season, realmId);
        if (userRp < rpRequired) revert Errors.InsufficientRealmPoints(userRp, rpRequired);

        // burn RP via signature
        REALM_POINTS.consume(realmId, rpRequired, consumeReasonCode, v, r, s);
        
        emit RealmPointsBurnt(realmId, rpRequired);
    }

//------------------------------------------------------------------------------

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGEMENT
    //////////////////////////////////////////////////////////////*/


    function setRouter(address router_) external onlyOwner {
        require(router_ != address(0), "Invalid address");
        
        address oldRouter = router;
        router = router_;
        
        emit RouterUpdated(oldRouter, router_);
    }
    
    /**
     * @notice To increase the duration of staking period and/or the rewards emitted
     * @dev Can increase rewards, duration MAY be extended. cannot reduce.
     * @param amount Amount of tokens by which to increase rewards
     * @param duration Amount of seconds by which to increase duration
     */
    function updateEmission(uint256 amount, uint256 duration) external onlyOwner {
        // either amount or duration could be 0. 
        if(amount == 0 && duration == 0) revert Errors.InvalidEmissionParameters();

        // get endTime - ensure its not exceeded
        uint256 endTime_ = endTime;
        require(block.timestamp < endTime_, "Staking over");

        // close the books
        (DataTypes.PoolAccounting memory pool_, ) = _updatePoolIndex();

        // updated values: amount or duration could be 0 
        uint256 unemittedRewards = pool_.totalPoolRewards - pool_.totalPoolRewardsEmitted;

        unemittedRewards += amount;
        uint256 newDurationLeft = endTime_ + duration - block.timestamp;
        
        // recalc: eps, endTime
        pool_.emissisonPerSecond = unemittedRewards / newDurationLeft;
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

        // usual blah blah checks
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _cache(vaultId, onBehalfOf);

        // check if vault has matured
        if(vault.endTime < block.timestamp) revert Errors.VaultNotMatured(vaultId); 
        if(userInfo.stakedNfts == 0 || userInfo.stakedNfts == 0) revert Errors.UserHasNothingStaked(vaultId, onBehalfOf);

        // revert if 0 balances of tokens or nfts?
        // if(userInfo_.stakedNfts < 0 || userInfo_.stakedTokens) revert 

        //get user balances
        uint256 stakedNfts = userInfo.stakedNfts;
        uint256 stakedTokens = userInfo.stakedTokens;
        
        //update balances: user + vault
        if(stakedNfts > 0){

            // record unstake with registry, else users cannot switch nfts to the new pool
            REGISTRY.recordUnstake(onBehalfOf, userInfo.tokenIds, vaultId);
            emit UnstakedMocaNft(onBehalfOf, vaultId, userInfo.tokenIds);       

            // update vault and user
            vault.stakedNfts -= stakedNfts;
            delete userInfo.stakedNfts;
            delete userInfo.tokenIds;
        }

        if(stakedTokens > 0){
            vault.stakedTokens -= stakedTokens;
            userInfo.stakedNfts -= stakedTokens;
            
            // burn stkMOCA
            _burn(onBehalfOf, stakedTokens);
            emit UnstakedMoca(onBehalfOf, vaultId, stakedTokens);       
        }

        // update storage 
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // return principal MOCA + NFT chip
        if(stakedTokens > 0) STAKED_TOKEN.safeTransfer(onBehalfOf, stakedTokens); 
    }


    /**
     * @notice Recover random tokens accidentally sent to the vault
     * @param tokenAddress Address of token contract
     * @param receiver Recepient of tokens
     * @param amount Amount to retrieve
     */
    function recoverERC20(address tokenAddress, address receiver, uint256 amount) external whenPaused onlyOwner {
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



/**

make getter fns:
 - get updated user state, wrt to rewards. cos it will be stale as per their last txn.
 */



 /**
     function unstakeNfts(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused {
        // usual blah blah checks
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // check if vault has matured
        if(block.timestamp < vault_.endTime) revert Errors.VaultNotMatured(vaultId);
        // revert if 0 balance
        if(userInfo_.stakedNfts == 0) revert Errors.UserHasNoNftStaked(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);
        
        uint256 stakedNfts = userInfo.stakedNfts;

        //update balances: user + vault
        userInfo.stakedNfts = 0;
        vault.stakedNfts -= stakedNfts;
        
        //_burn NFT chips?
        emit UnstakedMocaNft(onBehalfOf, vaultId, stakedNfts);   

        // return NFT chips
        LOCKED_NFT_TOKEN.safeTransfer(onBehalfOf, stakedNfts);
    }

    function unstakeTokens(bytes32 vaultId, address onBehalfOf) external whenStarted whenNotPaused {
        // usual blah blah checks
        require(vaultId > 0, "Invalid vaultId");

        // get vault + check if has been created
       (DataTypes.UserInfo memory userInfo_, DataTypes.Vault memory vault_) = _cache(vaultId, onBehalfOf);

        // check if vault has matured
        if(block.timestamp < vault_.endTime) revert Errors.VaultNotMatured(vaultId);
        // revert if 0 balance
        if(userInfo_.stakedTokens == 0) revert Errors.UserHasNoTokenStaked(vaultId, onBehalfOf);

        // update indexes and book all prior rewards
        (DataTypes.UserInfo memory userInfo, DataTypes.Vault memory vault) = _updateUserIndexes(onBehalfOf, userInfo_, vault_);

        //get user balances
        uint256 stakedTokens = userInfo.stakedTokens;
        
        //update balances: user + vault
        vault.stakedTokens -= stakedTokens;
        userInfo.stakedNfts -= stakedTokens;
        
        // burn stkMOCA
        _burn(onBehalfOf, stakedTokens);
        emit UnstakedMoca(onBehalfOf, vaultId, stakedTokens);       
    
        // update storage
        vaults[vaultId] = vault;
        users[onBehalfOf][vaultId] = userInfo;

        // return principal MOCA
        STAKED_TOKEN.safeTransfer(onBehalfOf, stakedTokens); 
    }
 
  */
