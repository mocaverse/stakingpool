// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2, stdStorage, StdStorage} from "forge-std/Test.sol";

// my contracts
import {Pool} from "../src/Pool.sol";
import {RewardsVault} from "../src/RewardsVault.sol";

import {MocaToken, ERC20} from "../src/MocaToken.sol";
import {NftRegistry} from "../src/NftRegistry.sol";

import {Errors} from "../src/Errors.sol";
import {DataTypes} from "../src/DataTypes.sol";

// interfaces
import {IPool} from "../src/interfaces/IPool.sol";
import {IRewardsVault} from "../src/interfaces/IRewardsVault.sol";

// external dep
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


abstract contract StateZero is Test {
    using stdStorage for StdStorage;

    // contracts
    Pool public stakingPool;
    RewardsVault public rewardsVault;

    // staking assets
    MocaToken public mocaToken;  
    NftRegistry public nftRegistry;      
    
    //address public REALM_POINTS;
    
    // stakingPool constructor data
    uint256 public startTime;           
    uint256 public duration;    
    uint256 public rewards;            
    string public name; 
    string public symbol;
    address public owner;
    uint256 public constant vaultBaseAllocPoints = 100 ether;    

    // testing data
    address public userA;
    address public userB;
    address public userC;
   
    uint256 public userAPrinciple;
    uint256 public userBPrinciple;
    uint256 public userCPrinciple;

//-------------------------------events-------------------------------------------
    event DistributionUpdated(uint256 indexed newPoolEPS, uint256 indexed newEndTime);

    event VaultCreated(address indexed creator, bytes32 indexed vaultId, uint40 indexed endTime, DataTypes.VaultDuration duration);
    event PoolIndexUpdated(address indexed asset, uint256 indexed oldIndex, uint256 indexed newIndex);
    event VaultIndexUpdated(bytes32 indexed vaultId, uint256 vaultIndex, uint256 vaultAccruedRewards);
    event UserIndexUpdated(address indexed user, bytes32 indexed vaultId, uint256 userIndex, uint256 userAccruedRewards);

    event StakedMoca(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
    event StakedMocaNft(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
    event UnstakedMoca(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
    event UnstakedMocaNft(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);

    event RewardsAccrued(address indexed user, uint256 amount);
    event NftFeesAccrued(address indexed user, uint256 amount);

    event RewardsClaimed(bytes32 indexed vaultId, address indexed user, uint256 amount);
    event NftRewardsClaimed(bytes32 indexed vaultId, address indexed creator, uint256 amount);
    event CreatorRewardsClaimed(bytes32 indexed vaultId, address indexed creator, uint256 amount);
//-----------------------------------------------------------------------------------

    function setUp() public virtual {
        owner = address(0xABCD);

        userA = address(0xA);
        userB = address(0xB);
        userC = address(0xC);

        userAPrinciple = 50 ether;
        userBPrinciple = 30 ether; 
        userCPrinciple = 80 ether; 

        startTime = 1;          // t = 1
        duration = 120 days;
        rewards = 120 days * 1 ether;

        vm.warp(0);
        vm.startPrank(owner);

        // deploy contracts
        mocaToken = new MocaToken("MocaToken", "MOCA");
        nftRegistry = new NftRegistry("bridgedMocaNft", "bMocaNft");

        //setup vault
        rewardsVault = new RewardsVault(IERC20(mocaToken), owner, owner);
        mocaToken.mint(owner, rewards);  
        mocaToken.approve(address(rewardsVault), rewards); 
        rewardsVault.deposit(owner, rewards);

        // IERC20 stakedToken, IERC20 lockedNftToken, IERC20 rewardToken, address realmPoints, address rewardsVault, uint128 startTime_, uint128 duration, uint128 rewards, 
        // string memory name, string memory symbol, address owner
        stakingPool = new Pool(IERC20(mocaToken), IERC20(nftRegistry), IERC20(mocaToken), address(0), address(rewardsVault), startTime, duration, rewards, "stkMOCA", "stkMOCA", owner);

        rewardsVault.setPool(address(stakingPool));

        //mint tokens to users
        mocaToken.mint(userA, userAPrinciple);
        mocaToken.mint(userB, userBPrinciple);
        mocaToken.mint(userC, userCPrinciple);

        // mint bridged NFT tokens to users
        nftRegistry.mint(userA, 1);
        nftRegistry.mint(userB, 1);
        nftRegistry.mint(userC, 2);

        vm.stopPrank();


        // approvals for receiving tokens for staking
        vm.prank(userA);
        mocaToken.approve(address(stakingPool), userAPrinciple);

        vm.prank(userB);
        mocaToken.approve(address(stakingPool), userBPrinciple);
        assertEq(mocaToken.allowance(userB, address(stakingPool)), userBPrinciple);

        vm.prank(userC);
        mocaToken.approve(address(stakingPool), userCPrinciple);
        
        // approval for issuing reward tokens to stakers
        vm.prank(address(rewardsVault));
        mocaToken.approve(address(stakingPool), rewards);


        //check stakingPool
        assertEq(stakingPool.startTime(), 1);
        assertEq(stakingPool.endTime(), 1 + 120 days);
        
        (
        uint256 totalAllocPoints, 
        uint256 emissisonPerSecond,
        uint256 poolIndex,
        uint256 poolLastUpdateTimeStamp,
        uint256 totalPoolRewards, 
        uint256 totalPoolRewardsEmitted) = stakingPool.pool();

        assertEq(totalAllocPoints, 0);
        assertEq(emissisonPerSecond, 1 ether);
        assertEq(poolIndex, 0);
        assertEq(poolLastUpdateTimeStamp, startTime);   
        assertEq(totalPoolRewards, rewards);
        assertEq(totalPoolRewardsEmitted, 0);

        // check rewards vault
        assertEq(rewardsVault.totalVaultRewards(), rewards);
        assertEq(rewardsVault.totalPaidRewards(), 0);


        // check time
        assertEq(block.timestamp, 0);
    }

    function getPoolStruct() public returns (DataTypes.PoolAccounting memory) {
        (
            uint256 totalAllocPoints, 
            uint256 emissisonPerSecond, 
            uint256 poolIndex, 
            uint256 poolLastUpdateTimeStamp,
            uint256 totalPoolRewards,
            uint256 totalPoolRewardsEmitted

        ) = stakingPool.pool();

        DataTypes.PoolAccounting memory pool;
        
        pool.totalAllocPoints = totalAllocPoints;
        pool.emissisonPerSecond = emissisonPerSecond;

        pool.poolIndex = poolIndex;
        pool.poolLastUpdateTimeStamp = poolLastUpdateTimeStamp;

        pool.totalPoolRewards = totalPoolRewards;
        pool.totalPoolRewardsEmitted = totalPoolRewardsEmitted;

        return pool;
    }

    function getUserInfoStruct(bytes32 vaultId, address user) public returns (DataTypes.UserInfo memory){
        (
            //bytes32 vaultId_, 
            uint256 stakedNfts, uint256 stakedTokens, 
            uint256 userIndex, uint256 userNftIndex,
            uint256 accStakingRewards, uint256 claimedStakingRewards,
            uint256 accNftStakingRewards, uint256 claimedNftRewards,
            uint256 claimedCreatorRewards

        ) = stakingPool.users(user, vaultId);

        DataTypes.UserInfo memory userInfo;

        {
            //userInfo.vaultId = vaultId_;
        
            userInfo.stakedNfts = stakedNfts;
            userInfo.stakedTokens = stakedTokens;

            userInfo.userIndex = userIndex;
            userInfo.userNftIndex = userNftIndex;

            userInfo.accStakingRewards = accStakingRewards;
            userInfo.claimedStakingRewards = claimedStakingRewards;

            userInfo.accNftStakingRewards = accNftStakingRewards;
            userInfo.claimedNftRewards = claimedNftRewards;

            userInfo.claimedCreatorRewards = claimedCreatorRewards;
        }

        return userInfo;
    }

    function getVaultStruct(bytes32 vaultId) public returns (DataTypes.Vault memory) {
        (
            bytes32 vaultId_, address creator,
            DataTypes.VaultDuration duration_, uint256 endTime_,
            
            uint256 multiplier, uint256 allocPoints,
            uint256 stakedNfts, uint256 stakedTokens,
            
            DataTypes.VaultAccounting memory accounting

        ) = stakingPool.vaults(vaultId);

        DataTypes.Vault memory vault;
        
        vault.vaultId = vaultId_;
        vault.creator = creator;

        vault.duration = duration_;
        vault.endTime = endTime_;

        vault.multiplier = multiplier;
        vault.allocPoints = allocPoints;

        vault.stakedNfts = stakedNfts;
        vault.stakedTokens = stakedTokens;

        vault.accounting = accounting;

        return vault;
    }

}

//Note:  t = 0. Pool deployed but not active yet.
contract StateZeroTest is StateZero {

    function testCannotCreateVault() public {
        vm.prank(userA);

        vm.expectRevert("Not started");
        
        uint8 salt = 1;
        uint256 creatorFee = 0.10 * 1e18;
        uint256 nftFee = 0.10 * 1e18;

        stakingPool.createVault(userA, salt, DataTypes.VaultDuration.THIRTY, creatorFee, nftFee);
    }

    function testCannotStake() public {
        vm.prank(userA);

        vm.expectRevert("Not started");
        
        bytes32 vaultId = bytes32(0);
        stakingPool.stakeTokens(vaultId, userA, userAPrinciple);
    }   

    function testEmptyVaults(bytes32 vaultId) public {
        
        DataTypes.Vault memory vault = getVaultStruct(vaultId);

        assertEq(vault.vaultId, bytes32(0));
        assertEq(vault.creator, address(0));   
    }
}



abstract contract StateT01 is StateZero {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(1);
    }
}

//Note: t=01, Pool deployed and active. But no one stakes.
//      discarded reward that is emitted.
//      see testDiscardedRewards() at the end.
contract StateT01Test is StateT01 {
    // placeholder


}

//Note: t=02, VaultA created. 
//      but no staking done. 
//      vault will accrued rewards towards bonusBall
abstract contract StateT02 is StateT01 {

    bytes32 public vaultIdA;

    uint8 public saltA = 123;
    uint256 public creatorFeeA = 0.10 * 1e18;
    uint256 public nftFeeA = 0.10 * 1e18;

    function setUp() public virtual override {
        super.setUp();

        vm.warp(2);

        vaultIdA = generateVaultId(saltA, userA);

        // create vault
        vm.prank(userA);       
        stakingPool.createVault(userA, saltA, DataTypes.VaultDuration.THIRTY, creatorFeeA, nftFeeA);
    }
    
    function generateVaultId(uint8 salt, address onBehalfOf) public view returns (bytes32) {
        return bytes32(keccak256(abi.encode(onBehalfOf, block.timestamp, salt)));
    }

}

contract StateT02Test is StateT02 {

    // cannot claim
    // cannot unstake

    function testNewVaultCreated() public {
        // check vault
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        assertEq(vaultA.vaultId, vaultIdA);
        assertEq(userA, vaultA.creator);
        assertEq(uint8(DataTypes.VaultDuration.THIRTY), uint8(vaultA.duration));
        assertEq(block.timestamp + 30 days, vaultA.endTime);   // 2592002 [2.592e6]

        assertEq(1, vaultA.multiplier);              // 30Day multiplier
        assertEq(100 ether, vaultA.allocPoints);     // baseAllocPoints: 1e20
        assertEq(0, vaultA.stakedNfts);
        assertEq(0, vaultA.stakedTokens);

        // accounting
        assertEq(0, vaultA.accounting.vaultIndex);
        assertEq(0, vaultA.accounting.vaultNftIndex);

        assertEq(creatorFeeA + nftFeeA, vaultA.accounting.totalFeeFactor);
        assertEq(creatorFeeA, vaultA.accounting.totalNftFeeFactor);
        assertEq(nftFeeA, vaultA.accounting.totalNftFeeFactor);

        assertEq(0, vaultA.accounting.totalAccRewards);
        assertEq(0, vaultA.accounting.accNftStakingRewards);
        assertEq(0, vaultA.accounting.accCreatorRewards);
        assertEq(0, vaultA.accounting.bonusBall);

        assertEq(0, vaultA.accounting.totalClaimedRewards);

    }

    function testCanStake() public {
        
        vm.prank(userA);
        stakingPool.stakeTokens(vaultIdA, userA, 1e18);
        // check events
        // check staking stuff
    }

    // vault created. therefore, poolIndex has been updated.
    function testPoolAccounting() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        
        // totalAllocPoints: 100, emissisonPerSecond: [1e18], 
        // poolIndex: 0, poolLastUpdateTimeStamp: 2, 
        // totalPoolRewards: 10368000000000000000000000 [1.036e25], totalPoolRewardsEmitted: 0

        assertEq(pool.totalAllocPoints, vaultBaseAllocPoints);   // 1 new vault w/ no staking
        assertEq(pool.emissisonPerSecond, 1 ether);
        
        assertEq(pool.poolIndex, 0);
        assertEq(pool.poolLastUpdateTimeStamp, startTime + 1);   

        assertEq(pool.totalPoolRewards, rewards);
        assertEq(pool.totalPoolRewardsEmitted, 0);
    }

}

//Note: t=03,  
//      userA stakes into VaultA and receives bonusBall reward. 
//      check bonusBall accrual on first stake.
abstract contract StateT03 is StateT02 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(3);

        vm.prank(userA);
        stakingPool.stakeTokens(vaultIdA, userA, userAPrinciple);
    }
}

//Note: check that all values are updated correctly after the 1st stake has been made into vaultA.
contract StateT03Test is StateT03 {

    // check tt staking was received and recorded correctly
    // check vault and userInfo

    function testPoolT03() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=2 to t=3, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
            No user has staked at the moment, so this is booked as bonusBall
             - rewardsAccruedPerToken = 1e18 / vaultBaseAllocPoint 
                                      = 1e18 / 100e18
                                      = 1e16
             - poolIndex should therefore be updated to 1e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta / totalAllocPoints) + oldIndex
             - eps: 1 
             - oldIndex: 0
             - timeDelta: 1 seconds 
             - totalAllocPoints: 100e18
            
            - poolIndex = (1 * 1 / 100e18 ) + 0 = 0.01 * 1e18 = 1e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple); // poolAllocPoints reset to match user's stake. no more vaultBaseAllocPoints
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex, 1e16);
        assertEq(pool.poolLastUpdateTimeStamp, 3);  

        assertEq(pool.totalPoolRewardsEmitted, 1 ether);
    }

    function testVaultAT03() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            userA has staked into vaultA
             - vault alloc points should be updated: baseVaultALlocPoint dropped, and overwritten w/ userA allocPoints
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
        */
        
        assertEq(vaultA.allocPoints, userAPrinciple);
        assertEq(vaultA.stakedTokens, userAPrinciple); 
       
        // indexes
        assertEq(vaultA.accounting.vaultIndex, 1e16); 
        assertEq(vaultA.accounting.vaultNftIndex, 0); 
        assertEq(vaultA.accounting.rewardsAccPerToken, 0); 

        // rewards (from t=2 to t=3)
        assertEq(vaultA.accounting.totalAccRewards, 1e18);               // bonusBall rewards
        assertEq(vaultA.accounting.accNftStakingRewards, 0);               // no tokens staked prior to t=3. no rewwards accrued
        assertEq(vaultA.accounting.accCreatorRewards, 0);                // no tokens staked prior to t=3. therefore no creator rewards       
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 0); 

    }

    function testUserAT03() public {

        DataTypes.UserInfo memory userA = getUserInfoStruct(vaultIdA, userA);

        /**
            vaultIndex = 1e16

            Calculating userIndex:
             grossUserIndex = 1e16
             totalFees = 0.2e18
             
             userIndex = [1e16 * (1 - 0.2e18) / 1e18] = [1e16 * 0.8e18] / 1e18 = 8e15
        */

        assertEq(userA.stakedTokens, userAPrinciple);

        assertEq(userA.userIndex, 0);   
        assertEq(userA.userNftIndex, 0);

        assertEq(userA.accStakingRewards, 1 ether);  // 1e18: bonusBall received
        assertEq(userA.claimedStakingRewards, 0);

        assertEq(userA.accNftStakingRewards, 0);
        assertEq(userA.claimedNftRewards, 0);
        assertEq(userA.claimedCreatorRewards, 0);
    }
}

//Note: t=04,  
//      userB stakes into VaultA. 
//      rewards emitted frm t=3 to t-4 is allocated to userA only.
abstract contract StateT04 is StateT03 {
    // 
    function setUp() public virtual override {
        super.setUp();

        vm.warp(4);

        vm.prank(userB);
        stakingPool.stakeTokens(vaultIdA, userB, userBPrinciple);
    }
}

contract StateT04Test is StateT04 {

    // check tt staking was received and recorded correctly
    // check pool, vault and userInfo

    function testPoolT04() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=3 to t=4, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / userAPrinciple
                                      = 1e18 / 50e18
                                      = 2e16
             - poolIndex should therefore be updated to 1e16 + 2e16 = 3e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 1e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 50e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 50e18 ) + 1e16 = 2e16 + 1e16 = 3e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple); 
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex, 3e16);
        assertEq(pool.poolLastUpdateTimeStamp, 4);  

        assertEq(pool.totalPoolRewardsEmitted, 2 ether);
    }

    function testVaultAT04() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            userA has staked into vaultA @t=3. userB has staked into vaultA @t=4.
            rewards emitted from t3 to t4, allocated to userA.
             - vault alloc points should be updated: sum of userA and userB principles (since multplier is 1)
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
            
            rewards & fees:
             incomingRewards = 1e18
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17

             totalAccRewards += incomingRewards = 1e18 + incomingRewards = 1e18 + 1e18 = 2e18
             
             rewardsAccPerToken += incomingRewards - fees / stakedTokens = (1e18 - 2e17)*1e18 / 50e18 = 1.6e16

        */
       
        //uint256 rewardsAccPerToken = (vaultA.accounting.vaultIndex - vaultA.accounting.accNftStakingRewards - vaultA.accounting.accCreatorRewards) / vaultA.stakedTokens;

        assertEq(vaultA.allocPoints, userAPrinciple + userBPrinciple);
        assertEq(vaultA.stakedTokens, userAPrinciple + userBPrinciple); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultA.accounting.vaultIndex, 3e16); 
        assertEq(vaultA.accounting.vaultNftIndex, 0); 
        assertEq(vaultA.accounting.rewardsAccPerToken, 1.6e16); 

        // rewards (from t=3 to t=4)
        assertEq(vaultA.accounting.totalAccRewards, 2e18);               
        assertEq(vaultA.accounting.accNftStakingRewards, 1e17);               // tokens staked. rewards accrued for 1st staker.
        assertEq(vaultA.accounting.accCreatorRewards, 1e17);                // no tokens staked prior to t=3. therefore no creator rewards       
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 0); 

    }

    // can't test A cos, A is stale. no action taken.

    function testUserBT04() public {

        DataTypes.UserInfo memory userB = getUserInfoStruct(vaultIdA, userB);

        /**
            Rewards:
             userB should have accrued 0 rewards. just staked at t4.

            Calculating userIndex:
             vaultIndex = 3e16
             grossUserIndex = 3e16
             totalFees = 0.2e18
             
             userIndex = [3e16 * (1e18 - 0.2e18) / 1e18] = [3e16 * 0.8e18] / 1e18 = 2.4e16

        */

        assertEq(userB.stakedTokens, userBPrinciple);

        assertEq(userB.userIndex, 1.6e16);   
        assertEq(userB.userNftIndex, 0);

        assertEq(userB.accStakingRewards, 0 ether);  
        assertEq(userB.claimedStakingRewards, 0);

        assertEq(userB.accNftStakingRewards, 0);
        assertEq(userB.claimedNftRewards, 0);
        assertEq(userB.claimedCreatorRewards, 0);
    }
}

//Note: t=05,  
//      both user have staked into vaultA at different times and sizes.
//      rewards emitted frm t=3 to t-4 is allocated to userA only.
//      rewards emitted frm t=4 to t=5 is allocated to both users, proportionally. 
abstract contract StateT05 is StateT04 {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(5);

        stakingPool.claimRewards(vaultIdA, userA);
        stakingPool.claimRewards(vaultIdA, userB);
    }
}


contract StateT05Test is StateT05 {

    function testPoolT05() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=4 to t=5, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / userAPrinciple + userBPrinciple
                                      = 1e18 / 80e18
                                      = 1.25e16
             - poolIndex should therefore be updated to 3e16 + 1.25e16 = 4.25e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 3e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 80e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 80e18 ) + 3e16 = 1.25e16 + 3e16 = 4.25e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple); 
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex, 4.25e16);
        assertEq(pool.poolLastUpdateTimeStamp, 5);  

        assertEq(pool.totalPoolRewardsEmitted, 3 ether);
    }

    function testVaultAT05() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            userA has staked into vaultA @t=3. userB has staked into vaultA @t=4.
            rewards emitted from t3 to t4, allocated to userA.
            rewards emitted frm t=4 to t=5 is allocated to both users, proportionally. 
             - vault alloc points should be updated: sum of userA and userB principles (since multplier is 1)
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
            
            rewards & fees:
             incomingRewards = 1e18
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17
             accNftStakingRewards = 1e18 * 0.1e18 / precision = 1e17
             
             accCreatorFee = 1e17 + 1e17 = 2e17
             accNftStakingRewards = 1e17 + 1e17 = 2e17
             totalAccRewards = totalAccRewards + incomingRewards = 2e18 + 1e18 = 3e18
             
             rewardsAccPerToken += incomingRewards - fees / 80e18 
                                 = (1e18 - 2e17)*1e18 / 80e18  + 1.6e16
                                 = 1e16 + 1.6e16
                                 = 2.6e16
        */
       
        assertEq(vaultA.allocPoints, userAPrinciple + userBPrinciple);
        assertEq(vaultA.stakedTokens, userAPrinciple + userBPrinciple); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultA.accounting.vaultIndex, 4.25e16); 
        assertEq(vaultA.accounting.vaultNftIndex, 0); 
        assertEq(vaultA.accounting.rewardsAccPerToken, 2.6e16);

        // rewards (from t=3 to t=4)
        assertEq(vaultA.accounting.totalAccRewards, 3e18);               
        assertEq(vaultA.accounting.accNftStakingRewards, 2e17);               // tokens staked. rewards accrued for 1st staker.
        assertEq(vaultA.accounting.accCreatorRewards, 2e17);                // no tokens staked prior to t=3. therefore no creator rewards       
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 2.3e18 + 3e17);          //userA: 2.3e18, userB: 3e17

        
        // check vault balances: initial rewards - claimedRewards
        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        assertEq(vaultBalance, rewards - vaultA.accounting.totalClaimedRewards);                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - vaultA.accounting.totalClaimedRewards);

        assertEq(rewardsVault.totalPaidRewards(), vaultA.accounting.totalClaimedRewards);

    }


    function testUserAT05() public {

        DataTypes.UserInfo memory userA = getUserInfoStruct(vaultIdA, userA);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            Rewards:
             userA should have accrued 
             bonusBall: 1e18 
             rewards from t3 to 4 = 1e18 * 0.8 = 8e17
             rewards from t4 to 5 = 1e18 * 0.8 * 50/80 = 5e17
            
            totalRewards = 2.3e18
             
            userIndex = vault.accounting.rewardsAccPerToken

        */

        assertEq(userA.stakedTokens, userAPrinciple);

        assertEq(userA.userIndex, vaultA.accounting.rewardsAccPerToken);  
        assertEq(userA.userNftIndex, 0);

        assertEq(userA.accStakingRewards, 2.3e18);  // 1e18: bonusBall received
        assertEq(userA.claimedStakingRewards, 2.3e18);

        assertEq(userA.accNftStakingRewards, 0);
        assertEq(userA.claimedNftRewards, 0);
        assertEq(userA.claimedCreatorRewards, 0);
    }

    function testUserBT05() public {

        DataTypes.UserInfo memory userB = getUserInfoStruct(vaultIdA, userB);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            Rewards:
             userB should have accrued 
             rewards from t3 to 4 = 1e18 * 0.8 * 30/80 = 3e17
            
            totalRewards = 3e17

            userIndex = vault.accounting.rewardsAccPerToken            
        */

        assertEq(userB.stakedTokens, userBPrinciple);

        assertEq(userB.userIndex, vaultA.accounting.rewardsAccPerToken); 
        assertEq(userB.userNftIndex, 0);

        assertEq(userB.accStakingRewards, 3e17); 
        assertEq(userB.claimedStakingRewards, 3e17);

        assertEq(userB.accNftStakingRewards, 0);
        assertEq(userB.claimedNftRewards, 0);
        assertEq(userB.claimedCreatorRewards, 0);

    }


}

//Note: t=06,  
//      userA will claim creator fees. 
//      creator fees will be applicable upon rewards emitted from t3 to t6.
//      rewards emitted frm t=2 to t=3 is categorised as bonusBall - not fees.
//      fees become applicable from the time of 1st stake, which is t=3. 
abstract contract StateT06 is StateT05 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(6);

        stakingPool.claimFees(vaultIdA, userA);
    }
}

contract StateT06Test is StateT06 {

    function testPoolT06() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=5 to t=6, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / userAPrinciple + userBPrinciple
                                      = 1e18 / 80e18
                                      = 1.25e16
             - poolIndex should therefore be updated to 4.25e16 + 1.25e16 = 5.5e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 4.25e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 80e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 80e18 ) + 4.25e16 = 1.25e16 + 4.25e16 = 5.5e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple); 
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex, 5.5e16);
        assertEq(pool.poolLastUpdateTimeStamp, 6);  

        assertEq(pool.totalPoolRewardsEmitted, 4 ether);
    }

    function testVaultAT06() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            rewards emitted frm t=5 to t=6 is allocated to both users, proportionally. 

             - vault alloc points should be updated: sum of userA and userB principles (since multplier is 1)
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
            
            rewards & fees: 
             [perUnitTime]
             incomingRewards = 1e18
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17
             accNftStakingRewards = 1e18 * 0.1e18 / precision = 1e17
             
             [total]
             accCreatorFee = 2e17 + 1e17 = 3e17
             accNftStakingRewards = 2e17 + 1e17 = 3e17
             totalAccRewards = totalAccRewards + incomingRewards = 3e18 + 1e18 = 4e18
             
              rewardsAccPerToken += incomingRewards - fees / 80e18 
                                 = (1e18 - 2e17)*1e18 / 80e18  + 2.6e16
                                 = 1e16 + 2.6e16
                                 = 3.6e16
        */
       
        assertEq(vaultA.allocPoints, userAPrinciple + userBPrinciple);
        assertEq(vaultA.stakedTokens, userAPrinciple + userBPrinciple); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultA.accounting.vaultIndex, 5.5e16); 
        assertEq(vaultA.accounting.vaultNftIndex, 0); 
        assertEq(vaultA.accounting.rewardsAccPerToken, 3.6e16); 

        // rewards (from t=3 to t=4)
        assertEq(vaultA.accounting.totalAccRewards, 4 ether);               
        assertEq(vaultA.accounting.accNftStakingRewards, 3e17);               // tokens staked. rewards accrued for 1st staker.
        assertEq(vaultA.accounting.accCreatorRewards, 3e17);                // no tokens staked prior to t=3. therefore no creator rewards       
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 2.3e18 + 3e17 + 3e17);          //userA: 2.3e18, userB: 3e17, creatorFee: 3e17

        // check vault balances: initial rewards - claimedRewards
        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - vaultA.accounting.totalClaimedRewards);                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - vaultA.accounting.totalClaimedRewards);

        assertEq(rewardsVault.totalPaidRewards(), vaultA.accounting.totalClaimedRewards);
    }

    function testUserAT06CreatorFee() public {

        DataTypes.UserInfo memory userA = getUserInfoStruct(vaultIdA, userA);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            Rewards:
             userA should have accrued 
             bonusBall: 1e18 
             rewards from t3 to 4 = 1e18 * 0.8 = 8e17
             rewards from t4 to 5 = 1e18 * 0.8 * 50/80 = 5e17
             rewards from t5 to 6 = 1e18 * 0.8 * 50/80 = 5e17
             
             totalRewards = 2.5e18

             accCreatorFee@t=6 = 3 * 1e18 * 0.1e17 = 3e17 [3 periods over which the fee was levied]
            
             totalRewards = 2.3e18 + 3e17
            
            userIndex
             vaultIndex * (1 - feeFactor) = 5.5e16 * 0.8 = 4.4e16

        */

        assertEq(userA.stakedTokens, userAPrinciple);

        assertEq(userA.userIndex,  vaultA.accounting.rewardsAccPerToken);                
        assertEq(userA.userNftIndex, 0);

        assertEq(userA.accStakingRewards, 2.5e18 + 3e17);          // 1e18: bonusBall received,  3e17: creatorFee
        assertEq(userA.claimedStakingRewards, 2.3e18);      

        assertEq(userA.accNftStakingRewards, 0);
        assertEq(userA.claimedNftRewards, 0);
        assertEq(userA.claimedCreatorRewards, 3e17);        // 3e17: creatorFee

    }
}


//Note: t=07,  
//      userC will create a new vault 
//      two active vaults.
abstract contract StateT07 is StateT06 {

    bytes32 public vaultIdC;

    uint8 public saltC = 22;
    uint256 public creatorFeeC = 0.10 * 1e18;
    uint256 public nftFeeC = 0.10 * 1e18;

    function setUp() public virtual override {
        super.setUp();

        vm.warp(7);

        vaultIdC = generateVaultId(saltC, userC);

        // create vault
        vm.prank(userC);       
        stakingPool.createVault(userC, saltC, DataTypes.VaultDuration.THIRTY, creatorFeeC, nftFeeC);
    }    
}

contract StateT07Test is StateT07 {

    function testPoolT07() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=6 to t=7, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / userAPrinciple + userBPrinciple
                                      = 1e18 / 80e18
                                      = 1.25e16
             - poolIndex should therefore be updated to 5.5e16 + 1.25e16 = 6.75e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 5.5e16 
             - timeDelta: 1 seconds 
             - totalAllocPoints: 80e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 80e18 ) + 5.5e16  = 1.25e16 + 5.5e16  = 6.75e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple + vaultBaseAllocPoints);    //vaultC now exists
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex, 6.75e16);
        assertEq(pool.poolLastUpdateTimeStamp, 7);  

        assertEq(pool.totalPoolRewardsEmitted, 5 ether);
    }

    function testNewVaultCCreated() public {
        // check vault
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        assertEq(vaultC.creator, userC);
        assertEq(uint8(vaultC.duration), uint8(DataTypes.VaultDuration.THIRTY));
        assertEq(vaultC.endTime, block.timestamp + 30 days);   

        assertEq(vaultC.multiplier, 1);              // 30Day multiplier
        assertEq(vaultC.allocPoints, 100 ether);     // baseAllocPoints: 1e20
        assertEq(vaultC.stakedNfts, 0);
        assertEq(vaultC.stakedTokens, 0);

        // accounting
        assertEq(vaultC.accounting.vaultIndex, 6.75e16);
        assertEq(vaultC.accounting.vaultNftIndex, 0);
        assertEq(vaultC.accounting.rewardsAccPerToken, 0); 

        assertEq(vaultC.accounting.totalFeeFactor, creatorFeeC + nftFeeC);
        assertEq(vaultC.accounting.creatorFeeFactor, creatorFeeC);
        assertEq(vaultC.accounting.totalNftFeeFactor, nftFeeC);

        assertEq(vaultC.accounting.totalAccRewards, 0);
        assertEq(vaultC.accounting.accNftStakingRewards, 0);
        assertEq(vaultC.accounting.accCreatorRewards, 0);
        assertEq(vaultC.accounting.bonusBall, 0);

        assertEq(vaultC.accounting.totalClaimedRewards, 0);

    }
}

//Note: t=08,  
//      two concurrently active vaults.
//      rewards emitted frm t=7 to t=8 is proportionally split across both vaults as per weightage
//      userC stakes into vaultC. 1st staker, beneficiary of bonusBall.
//      vault's alloc points are overwritten, reflective of staked amount 
abstract contract StateT08 is StateT07 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(8);

        vm.prank(userC);
        stakingPool.stakeTokens(vaultIdC, userC, userCPrinciple / 2);
    }    
}

contract StateT08Test is StateT08 {
    function testPoolT08() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=7 to t=8, Pool emits 1e18 rewards
            There are 2 vaults in existence, receiving a proportional split of rewards:
             
             vaultA allocPoints = userAPrinciple + userBPrinciple = 80e18
             vaultC allocPoints = vaultBaseAllocPoints = 100e18
            
            totalAllocPoints = 80e18 + 100e18 = 180e18


             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / 180e18
                                      = 5.555555... e15
             - poolIndex should therefore be updated to 6.75e16 + 5.55e15 = 7.305e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 6.75e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 180e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 180e18 ) + 6.75e16  = 5.55e15 + 6.75e16  = 7.305e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple + userCPrinciple/2);    //vaultC now exists
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 7.305e16/1e13);     //rounding: to negate recurring decimals
        assertEq(pool.poolLastUpdateTimeStamp, 8);  

        assertEq(pool.totalPoolRewardsEmitted, 6 ether);
    }

    function testVaultCT08() public {

        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /** 
            1st staking action into vaultC; by userC.
            rewards emitted frm t=7 to t=8 is allocated to userC as bonusBall 

             - vault alloc points should be updated: userCPrinciple/2
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
            
            rewards & fees: 
             [perUnitTime]
             incomingRewards = 1e18 / 180e18 * 100e18 = 5.55555e17
             accCreatorFee = 0
             accNftStakingRewards = 0
             
             [total]
             accCreatorFee = 0
             accNftStakingRewards = 0
             totalAccRewards = 5.55555e17
             bonusBall = 5.55555e17
        */
       
        assertEq(vaultC.allocPoints, userCPrinciple/2);
        assertEq(vaultC.stakedTokens, userCPrinciple/2); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultC.accounting.vaultIndex/1e13, 7.305e16/1e13);             //rounding: to negate recurring decimals
        assertEq(vaultC.accounting.vaultNftIndex, 0); 
        assertEq(vaultC.accounting.rewardsAccPerToken, 0);                      //0 cos nothing staked thus far.

        // rewards (from t=3 to t=4)
        assertEq(vaultC.accounting.totalAccRewards/1e14, 5.555e17/1e14);             //rounding: to negate recurring decimals    
        assertEq(vaultC.accounting.accNftStakingRewards, 0);              
        assertEq(vaultC.accounting.accCreatorRewards, 0);                
        assertEq(vaultC.accounting.bonusBall/1e14, 5.555e17/1e14);                   //rounding: to negate recurring decimals

        assertEq(vaultC.accounting.totalClaimedRewards, 0);     
      
    }

    function testUserCT08() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            Rewards:
             userC should have accrued 
             bonusBall: 5.555..5e17
             
             totalRewards = 5.555..5e17
        */

        assertEq(userC.stakedTokens, userCPrinciple/2);

        assertEq(userC.userIndex,  vaultC.accounting.rewardsAccPerToken); 
        assertEq(userC.userNftIndex, 0);

        assertEq(userC.accStakingRewards/1e14, 5.555e17/1e14);          // bonusBall received
        assertEq(userC.claimedStakingRewards, 0);      

        assertEq(userC.accNftStakingRewards, 0);
        assertEq(userC.claimedNftRewards, 0);
        assertEq(userC.claimedCreatorRewards, 0);        


        // bonusBall: 555555555555555500 [5.555e17]
        // 
    }

}

//Note: t=09,  
//      two concurrently active vaults.
//      rewards emitted frm t=8 to t=9 are proportionally split across both vaults as per weightage.
//      userC stakes into vaultC again.
abstract contract StateT09 is StateT08 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(9);

        vm.prank(userC);
        stakingPool.stakeTokens(vaultIdC, userC, userCPrinciple / 2);
    }    
}

contract StateT09Test is StateT09 {

    function testPoolT09() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=8 to t=9, Pool emits 1e18 rewards
            There are 2 vaults in existence, receiving a proportional split of rewards:
             
             vaultA allocPoints = userAPrinciple + userBPrinciple = 80e18
             vaultC allocPoints = userCPrinciple = 80e18
            
            totalAllocPoints = 80e18 + 80e18 = 160e18


             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / 120e18
                                      = 8.333e15
             - poolIndex should therefore be updated to 7.305e16 + 8.333e15 = 8.138e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 7.305e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 120e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 120e18 ) + 7.305e16 = 8.333e15 + 7.305e16  = 8.138e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple + userCPrinciple);    //vaultC now exists
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 8.138e16/1e13);     //rounding: to negate recurring decimals
        assertEq(pool.poolLastUpdateTimeStamp, 9);  

        assertEq(pool.totalPoolRewardsEmitted, 7 ether);
    }


    function testVaultCT09() public {
        
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /** 
            2nd staking action into vaultC; by userC.
            rewards emitted frm t=7 to t=8 is allocated to userC as bonusBall 
            rewards emitted frm t=8 to t=9 is allocated to userC as per userC's allocPoints (userCPrinciple/2)
            fees are applied frm t=8 to t=9

             - vault alloc points should be updated: userCPrinciple
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
            
            rewards & fees: 
             [perUnitTime]
             incomingRewards = 1e18 / 120e18 * 40e18 = 3.33333e17
             accCreatorFee = 3.33333e17 * 0.1e18 / precision = 3.33333e16
             accNftStakingRewards = 3.33333e17 * 0.1e18 / precision = 3.33333e16
             
             [total]
             accCreatorFee = 3.33333e16
             accNftStakingRewards = 3.33333e16
             totalAccRewards = 5.55555e17 + 3.33333e17 = 8.8888e17
             bonusBall = 5.55555e17

             rewardsAccPerToken += incomingRewards - fees / 40e18 
                                 = (3.33333e17 - 6.666e16)*1e18 / 40e18  + 0
                                 = ~ 6.666e15 + 0
                                 = ~ 6.666e15 
        */
       
        assertEq(vaultC.stakedTokens, userCPrinciple); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultC.accounting.vaultIndex/1e13, 8.138e16/1e13);             //rounding: to negate recurring decimals
        assertEq(vaultC.accounting.vaultNftIndex, 0); 
        assertEq(vaultC.accounting.rewardsAccPerToken/1e12, 6.666e15/1e12); 

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards/1e14, 8.888e17/1e14);             //rounding: to negate recurring decimals    
        assertEq(vaultC.accounting.accNftStakingRewards/1e12, 3.3333e16/1e12);              
        assertEq(vaultC.accounting.accCreatorRewards/1e12, 3.3333e16/1e12);                
        assertEq(vaultC.accounting.bonusBall/1e14, 5.555e17/1e14);                   //rounding: to negate recurring decimals

        assertEq(vaultC.accounting.totalClaimedRewards, 0);     
      
    }
    
    function testUserCT09() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            userIndex
             vaultIndex * (1 - feeFactor) = 8.1388888e16 * 0.8 = 6.5111111e16

            Rewards: (referencing prior VaultC's calc)
             userC should have accrued 
             bonusBall: 5.555..5e17
             rewards: 3.33333e17
             total = 8.8888e17

            Rewards received (actual User calc.)
             received = userIndexDelta * allocPoints
                      = (6.5111111e16 - 5.844e16) * 40e18
                      = 2.66844..4e17
             total = bonusBall + 2.66844..4e17
                   =  5.555..5e17 + 2.66844..4e17
                   =  ~ 8.223944e17
        */

        assertEq(userC.stakedTokens, userCPrinciple);

        assertEq(userC.userIndex,  vaultC.accounting.rewardsAccPerToken);            // rounding    
        assertEq(userC.userNftIndex, 0);

        assertEq(userC.accStakingRewards/1e14, 8.222e17/1e14);          // bonusBall received
        assertEq(userC.claimedStakingRewards, 0);      

        assertEq(userC.accNftStakingRewards, 0);
        assertEq(userC.claimedNftRewards, 0);
        assertEq(userC.claimedCreatorRewards, 0);        

    }

}

//Note: t=10,  
//      two concurrently active vaults.
//      rewards emitted frm t=9 to t=10 are proportionally split across both vaults as per weightage.
//      userC claims rewards
abstract contract StateT10 is StateT09 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(10);

        // update vaults
        stakingPool.claimRewards(vaultIdC, userC);
    }    
}

contract StateT10Test is StateT10 {

    function testPoolT10() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=9 to t=10, Pool emits 1e18 rewards
            There are 2 vaults in existence, receiving a proportional split of rewards:
             
             vaultA allocPoints = userAPrinciple + userBPrinciple = 80e18
             vaultC allocPoints = userCPrinciple = 80e18
            
            totalAllocPoints = 80e18 + 80e18 = 160e18


             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / 160e18
                                      = 6.25e15
             - poolIndex should therefore be updated to 8.138e16 + 6.25e15 = 8.763e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 8.138e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 160e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 160e18 ) + 8.138e16 = 6.25e15 +  8.138e16 = 8.763e16 
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple + userCPrinciple);    //vaultC now exists
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 8.763e16/1e13);     //rounding: to negate recurring decimals
        assertEq(pool.poolLastUpdateTimeStamp, 10);  

        assertEq(pool.totalPoolRewardsEmitted, 8 ether);
    }

    function testVaultCT10() public {
        
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /** 
            2nd staking action into vaultC; by userC.
            rewards emitted frm t=7 to t=8 is allocated to userC as bonusBall 
            rewards emitted frm t=8 to t=9 is allocated to userC as per userC's allocPoints (userCPrinciple/2)
            rewards emitted frm t=9 to t=10 is allocated to userC as per userC's allocPoints (userCPrinciple)

            fees are applied frm t=9 to t=10

             - vault alloc points should be updated: userCPrinciple
             - stakedTokens updated
             - vaultIndex updated
             - fees updated
             - rewards updated
            
            rewards & fees: 
             [perUnitTime]
             incomingRewards = 1e18 / 160e18 * 80e18 = 5e17
             accCreatorFee = 5e17 * 0.1e18 / precision =  5e16
             accNftStakingRewards = 5e17 * 0.1e18 / precision = 5e16
             
             [total]
             accCreatorFee = 3.33333e16 + 5e16 = 8.333e16
             accNftStakingRewards = 3.33333e16 + 5e16 = 8.333e16
             totalAccRewards = 5.55555e17 + 3.33333e17 + 5e17 = 1.3888e18
             bonusBall = 5.55555e17

             claimableRewards = total - nft - creator 
                              = 1.388e18 - 8.333e16 - 8.333e16
                              = ~ 1.222e18
             
             rewardsAccPerToken += incomingRewards - fees / 80e18 
                                 = (5e17 - 5e16 - 5e16) * 1e18 / 80e18  + 6.666e15 
                                 = ~ 5e15 + 6.666e15 
                                 = ~ 1.1666e16
        */
       
        assertEq(vaultC.allocPoints, userCPrinciple);
        assertEq(vaultC.stakedTokens, userCPrinciple); 
        assertEq(vaultC.accounting.rewardsAccPerToken/1e13, 1.166e16/1e13); 

        // indexes: in-line with poolIndex
        assertEq(vaultC.accounting.vaultIndex/1e13, 8.763e16/1e13);             //rounding: to negate recurring decimals
        assertEq(vaultC.accounting.vaultNftIndex, 0); 

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards/1e15, 1.388e18/1e15);             //rounding: to negate recurring decimals    
        assertEq(vaultC.accounting.accNftStakingRewards/1e13, 8.333e16/1e13);              
        assertEq(vaultC.accounting.accCreatorRewards/1e13, 8.333e16/1e13);                
        assertEq(vaultC.accounting.bonusBall/1e14, 5.555e17/1e14);                   //rounding: to negate recurring decimals

        assertEq(vaultC.accounting.totalClaimedRewards/1e15, 1.222e18/1e15);     
      
        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

    }

    function testUserCT10() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            userIndex
             vaultIndex * (1 - feeFactor) = 8.763e16 * 0.8 = 7.0104e16 ~ 7.011e16

            Rewards: (referencing prior VaultC's calc)
             userC should have accrued 
             bonusBall: 5.555..5e17
             rewards: 3.33333e17 + 4e17
             total = ~1.222e18

            Rewards received (actual User calc.)
             received = userIndexDelta * allocPoints
                      = (7.011e16 - 6.511e16) * 80e18
                      = 4e17
             total = bonusBall + 2.66844..4e17 + 4e17
                   =  5.555..5e17 + 2.66844..4e17 + 4e17
                   =  ~ 1.222e18
        */

        assertEq(userC.stakedTokens, userCPrinciple);

        assertEq(userC.userIndex, vaultC.accounting.rewardsAccPerToken);
        assertEq(userC.userNftIndex, 0);

        assertEq(userC.accStakingRewards/1e15, 1.222e18/1e15);          // bonusBall received
        assertEq(userC.claimedStakingRewards/1e15, 1.222e18/1e15);      

        assertEq(userC.accNftStakingRewards, 0);
        assertEq(userC.claimedNftRewards, 0);
        assertEq(userC.claimedCreatorRewards, 0);        

    }
}

//Note: t=2 + 30days,  | 2,592,002
//      vault A ends
//      userA claims rewards 
//      check userA and userB.
abstract contract StateVaultAEnds is StateT10 {

    function setUp() public virtual override {
        super.setUp();

        uint256 vaultAEndtTime = 2 + 30 days;   // 2,592,002
        vm.warp(vaultAEndtTime);

        // update vaults
        stakingPool.claimRewards(vaultIdA, userA);
    }    
}

contract StateVaultAEndsTest is StateVaultAEnds {

    function testPoolVaultAEnds() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=10 to t=2,592,002, Pool emits 1e18 rewards, per sec.
            There are 2 vaults in existence, receiving a proportional split of rewards:
             
             vaultA allocPoints = userAPrinciple + userBPrinciple = 80e18
             vaultC allocPoints = userCPrinciple = 80e18
            
            totalAllocPoints = 80e18 + 80e18 = 160e18
            totalRewardsEmitted = 2,592,002 - 10 = 2,591,992e18
             
             - rewardsAccruedPerToken = totalRewardsEmitted / totalAllocPoints 
                                      = 2,591,992e18 / 160e18
                                      = 16199.95e18
             - poolIndex should therefore be updated to 8.763e16 + 16199.95e18 = ~ 1.622e22 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex:  8.763e16 
             - timeDelta: 2,591,992 seconds 
             - totalAllocPoints: 160e18
            
            - poolIndex = (1e18 * 2,591,992 * 1e18 / 160e18 ) + 8.763e16 = 1.619995e22 + 8.763e16 = ~ 1.622e22
        */

        assertEq(pool.totalAllocPoints, userAPrinciple + userBPrinciple + userCPrinciple);    //vaultC now exists
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e18, 1.62e22/1e18);             //rounding: to negate recurring decimals
        assertEq(pool.poolLastUpdateTimeStamp, 2_592_002);  

        assertEq(pool.totalPoolRewardsEmitted, 2_592_000 ether);
    }

    function testVaultATEnds() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            Total rewards accrued by vaultA
             startTime = 2, endTime = 2,592,002 (30 days)
             
             t2 - t3: 1e18 (bonusBall)
             t3 - t7: 4e18 (userA stakes at t3)
             t7 - t8: 1e18 * 80/180 = 4.444e17  (vaultC created at t7)
             t8 - t9: 1e18 * 80/120 = 6.666e17  (userC stakes at t8)
             t9 - t10: 1e18 * 80/160 = 5e17     (userC stakes again at t9)
             
             t10 - tEnd: 
              timeDelta = 2,592,002 - 10 = 2,591,992
              rewardsEmittedByPool = 2,591,992 e18
              vaultARewards = 2,591,992 e18 * 80/160
                            = 1,295,996 e18 

            Total Rewards:
             1e18 + 4e18 + 4.444e17 + 6.666e17 + 5e17 + 1,295,996e18
             = 1.296002611 × 10^24
             ~ 1.296e24

            Total Fees:
              totalRewards * feeFactor = 1.296e24 * 0.2 = 2.592e23
              accCreatorFee = 1.296e24 * 0.1 = 1.296e23
              totalAccRewards = 1.296e24 * 0.1 = 1.296e23
             
            Calculating rewardsAccPerToken:
             rewards received: 
              t6 - 7: 1e18
              t7 - t10: 4.444e17 + 6.666e17 + 5e17
              t10 - t2_592_002: 1,295,996 e18
            
             totalRewards = ~ 1.2959e24
             totalRewardsLessFees = ~ 1.0367e24

             [t6 - t2_592_002]
             rewardsAccPerToken += incomingRewards - fees / 80e18 
                                 = (1.0367e24) * 1e18 / 80e18  
                                 = ~ 1.29599e22
             
             [t2 - t6]:  3.6e16 

             rewardsAccPerToken = 3.6e16 + 1.29599e22
                                = 1.295990036e22
                                = ~ 1.296e22

            userA claim: (t10 - t2_592_002)
             
        */

        uint256 claimedRewards = mocaToken.balanceOf(userA) + mocaToken.balanceOf(userB);
        uint256 calcClaimedRewards = (6.48e23 + 3e17 + 3e17);                           //userA: 6.48e23, userB: 3e17, creatorFee: 3e17

        assertEq(vaultA.allocPoints, userAPrinciple + userBPrinciple);
        assertEq(vaultA.stakedTokens, userAPrinciple + userBPrinciple); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultA.accounting.vaultIndex/1e18, 1.62e22/1e18);  
        assertEq(vaultA.accounting.vaultNftIndex, 0); 
        assertEq(vaultA.accounting.rewardsAccPerToken/1e19, 1.296e22/1e19);  

        // rewards (from t=3 to t=4)
        assertEq(vaultA.accounting.totalAccRewards/1e21, 1.296e24/1e21);               
        assertEq(vaultA.accounting.accNftStakingRewards/1e20, 1.296e23/1e20);               // tokens staked. rewards accrued for 1st staker.
        assertEq(vaultA.accounting.accCreatorRewards/1e20, 1.296e23/1e20);                // no tokens staked prior to t=3. therefore no creator rewards       
        assertEq(vaultA.accounting.bonusBall, 1e18); 
        
        assertEq(claimedRewards/1e20, calcClaimedRewards/1e20);                  
        assertEq(vaultA.accounting.totalClaimedRewards, claimedRewards);                   //userA: 6.48e23, userB: 3e17, creatorFee: 3e17

        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

    } 

    function testUserAVaultAEnds() public {

        DataTypes.UserInfo memory userA = getUserInfoStruct(vaultIdA, userA);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);
        
        /**
            Rewards:
             userA should have accrued 
             t2 to 3: bonusBall: 1e18 
             rewards from t3 to 4 = 1e18 * 0.8 = 8e17
             rewards from t4 to 5 = 1e18 * 0.8 * 50/80 = 5e17
             rewards from t5 to 6 = 1e18 * 0.8 * 50/80 = 5e17
             rewards from t6 to 7 = 1e18 * 0.8 * 50/80 = 5e17   

             rewards from t7 to 8 = 4.444e17 * 0.8 * 50/80 = 2.222e17   (vaultC created at t7)
             rewards from t8 to 9 = 6.666e17 * 0.8 * 50/80 = 3.333e17   (userC stakes at t8)
             rewards from t8 to 9 = 5e17 * 0.8 * 50/80 = 2.5e17         (userC stakes again at t9)
             
             rewards from t9 to 2,592,002 = (5e17 * 0.8 * 50/80) * 2_591_993 = 6.4799825e23

             totalRewards = ~ 6.48e23
                
             accCreatorFee = totalRewards * 0.1 = ~ 6.48e22

        */

        assertEq(userA.stakedTokens, userAPrinciple);

        assertEq(userA.userIndex/1e18,  1.296e22/1e18);                
        assertEq(userA.userNftIndex, 0);
        assertEq(userA.userIndex,  vaultA.accounting.rewardsAccPerToken);

        // accStakingRewards == claimed 
        assertEq(userA.accStakingRewards, userA.claimedStakingRewards);      
        assertEq(userA.accStakingRewards/1e20, 6.48e23/1e20);           
        assertEq(userA.claimedStakingRewards/1e20, 6.48e23/1e20);      

        assertEq(userA.accNftStakingRewards, 0);
        assertEq(userA.claimedNftRewards, 0);
        assertEq(userA.claimedCreatorRewards, 3e17);        // 3e17: creatorFee
    }

    function testUsersCanUnstake() public {
        // mcoa tokens
        uint256 preMocaBalanceA = mocaToken.balanceOf(userA);
        uint256 preMocaBalanceB = mocaToken.balanceOf(userB);
        // stkMoca tokens
        uint256 preStkMocaBalanceA = stakingPool.balanceOf(userA);
        uint256 preStkMocaBalanceB = stakingPool.balanceOf(userB);

        stakingPool.unstakeAll(vaultIdA, userA);
        stakingPool.unstakeAll(vaultIdA, userB);
        
        // mcoa tokens
        uint256 postMocaBalanceA = mocaToken.balanceOf(userA);
        uint256 postMocaBalanceB = mocaToken.balanceOf(userB);
        // stkMoca tokens
        uint256 postStkMocaBalanceA = stakingPool.balanceOf(userA);
        uint256 postStkMocaBalanceB = stakingPool.balanceOf(userB);

        // get data
        DataTypes.UserInfo memory userAInfo = getUserInfoStruct(vaultIdA, userA);
        DataTypes.UserInfo memory userBInfo = getUserInfoStruct(vaultIdA, userB);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);
        
        // check moca token balances: pre should be 0, unless claimed rewards 
        // userA claimed rewards at t5: 6.48e23 | creatorFee: 3e17
        assertEq(preMocaBalanceA,  userAInfo.claimedStakingRewards + userAInfo.claimedCreatorRewards);              
        assertEq(postMocaBalanceA, userAPrinciple + userAInfo.claimedStakingRewards + userAInfo.claimedCreatorRewards);
        // userB claimed rewards at t5: 3e17
        assertEq(preMocaBalanceB, userBInfo.claimedStakingRewards);              
        assertEq(postMocaBalanceB, userBPrinciple + userBInfo.claimedStakingRewards);

        // check stkMoca token balances: 0 after unstaking
        assertEq(postStkMocaBalanceA, 0);
        assertEq(preStkMocaBalanceA, userAPrinciple);

        assertEq(postStkMocaBalanceB, 0);
        assertEq(preStkMocaBalanceB, userBPrinciple); 
    }

}


//Note: t=2 + 30days + 1,  | 2,592,003
//      1 second after vaultA has ended
//      ensure update indexes remain static.
abstract contract StateT2_592_003 is StateVaultAEnds {

    function setUp() public virtual override {
        super.setUp();

        uint256 vaultAEndtTimePlusOne = 2 + 30 days + 1;   // 2,592,003
        vm.warp(vaultAEndtTimePlusOne);

        // vault index should not be updated since ended
        stakingPool.updateVault(vaultIdA);
    }   
}

contract StateT2_592_003Test is StateT2_592_003 {

    function testVaultAIndexNotUpdated() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        // indexes: in-line with poolIndex@t2_592_002
        assertEq(vaultA.accounting.vaultIndex/1e18, 1.62e22/1e18); 
        assertEq(vaultA.accounting.vaultNftIndex, 0); 
        assertEq(vaultA.accounting.rewardsAccPerToken/1e19, 1.296e22/1e19);  

    }

    function testUserBData() public {

        vm.prank(userB);
        stakingPool.claimRewards(vaultIdA, userB);

        DataTypes.UserInfo memory userBInfo = getUserInfoStruct(vaultIdA, userB);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);
        
        /**
            Rewards:
             userB should have accrued 
             rewards from t4 to 5 = 1e18 * 0.8 * 30/80 = 5e17
             rewards from t5 to 6 = 1e18 * 0.8 * 30/80 = 5e17
             rewards from t6 to 7 = 1e18 * 0.8 * 30/80 = 5e17   

             rewards from t7 to 8 = 4.444e17 * 0.8 * 30/80 = 1.333e17   (vaultC created at t7)
             rewards from t8 to 9 = 6.666e17 * 0.8 * 30/80 = 1.999e17   (userC stakes at t8)
             rewards from t8 to 9 = 5e17 * 0.8 * 30/80     = 1.5e17     (userC stakes again at t9)
             
             rewards from t9 to 2,592,002 = (5e17 * 0.8 * 30/80) * 2_591_993 = 3.887e23

             totalRewards = ~ 3.888e23
        */

        assertEq(userBInfo.stakedTokens, userBPrinciple);

        assertEq(userBInfo.userIndex,  vaultA.accounting.rewardsAccPerToken);
        assertEq(userBInfo.userNftIndex, 0);

        // accStakingRewards == claimedRewards
        assertEq(userBInfo.accStakingRewards/1e20, 3.888e23/1e20);           
        assertEq(userBInfo.claimedStakingRewards/1e20, 3.888e23/1e20);      

        assertEq(userBInfo.accNftStakingRewards, 0);
        assertEq(userBInfo.claimedNftRewards, 0);
        assertEq(userBInfo.claimedCreatorRewards, 0);        // 3e17: creatorFee  

        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

    }

    function testUserBCanUnstake() public {

        uint256 priorStakedBalance = stakingPool.balanceOf(userB);

        vm.prank(userB);
        stakingPool.unstakeAll(vaultIdA, userB);

        uint256 currentStakedBalance = stakingPool.balanceOf(userB);

        assertEq(currentStakedBalance, 0);                       // nothing staked
        assertEq(priorStakedBalance, userBPrinciple);            // initially staked was accurate


    }

    function testUserBCanClaim() public {

        vm.prank(userB);
        stakingPool.claimRewards(vaultIdA, userB);
        
        uint256 currentStakedBalance = stakingPool.balanceOf(userB);
        uint256 currentMocaBalance = mocaToken.balanceOf(userB);

        /**
            Rewards:
             userB should have accrued 
             rewards from t4 to 5 = 1e18 * 0.8 * 30/80 = 5e17
             rewards from t5 to 6 = 1e18 * 0.8 * 30/80 = 5e17
             rewards from t6 to 7 = 1e18 * 0.8 * 30/80 = 5e17   

             rewards from t7 to 8 = 4.444e17 * 0.8 * 30/80 = 1.333e17   (vaultC created at t7)
             rewards from t8 to 9 = 6.666e17 * 0.8 * 30/80 = 1.999e17   (userC stakes at t8)
             rewards from t8 to 9 = 5e17 * 0.8 * 30/80     = 1.5e17     (userC stakes again at t9)
             
             rewards from t9 to 2,592,002 = (5e17 * 0.8 * 30/80) * 2_591_993 = 3.887e23

             totalRewards = ~ 3.888e23
        */

        assertEq(currentStakedBalance, userBPrinciple);                       // staked amount unchanged
        assertEq(currentMocaBalance/1e20, 3.888e23/1e20);            
    }
}


//Note: t= 7 + 30days,  | 2,592,007
//      vault C ends
//      userC unstakesAll upon vault.EndTime
abstract contract StateTVaultCEnds is StateT2_592_003 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(7 + 30 days);  // 2592007

        // unstake all - to update all user's states
        stakingPool.unstakeAll(vaultIdA, userA);
        stakingPool.unstakeAll(vaultIdA, userB);

        stakingPool.unstakeAll(vaultIdC, userC);
    }   
}

contract StateTVaultCEndsTest is StateTVaultCEnds {

    function testPoolVaultCEnds() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();

        /**
            Pool emits 1e18 rewards, per sec.
             At t=2,592,002: poolIndex = ~ 1.622e22

             From t=2,592,002 to t=2,592,007, vaultC is the sole beneficiary of pool rewards
             rewardsAccrued = 1e18 * (2,592,007 - 2,592,002)
                            = 5e18
             
             This tallies as vaultC was created at t7, while vaultA was created at t2, accounting for a 5 sec delta.
             (VaultC ends 5s after vaultA ends). 
             totalAllocPoints = totalStaked * multplier 
                              = userCPrinciple * 1
                              = 80e18 
             
             rewardsAccruedPerToken = totalRewardsEmitted / totalAllocPoints 
                                    = 5e18 / 80e18
                                    = 6.25e16
            
            Therefore, poolIndex at t=2,592,007 = priorPoolIndex + rewardsAccruedPerTokenSince 
                                                = 1.622e22 + 6.25e16
                                                = 1.62200625e22       (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex:  1.622e22
             - timeDelta: 5 seconds 
             - totalAllocPoints: 80e18
            
            - poolIndex = (1e18 * 5 * 1e18 / 80e18 ) + 1.622e22 = 6.25e16 + 1.622e22 = ~ 1.622e22

            On totalPoolRewardsEmitted:
             - pool only begins emitting rewards when the first vault is created. 
             - so from t=0 to t=2, nothing was emitted. 
             - hence at this time, the totalPoolRewardsEmitted is the number of seconds in ether, less 2. 
        */

        assertEq(pool.totalAllocPoints, 0);                        
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e18, 1.62e22/1e18);             //rounding: to negate recurring decimals
        assertEq(pool.poolLastUpdateTimeStamp, 2_592_007);  

        assertEq(pool.totalPoolRewardsEmitted, (2_592_007 - 2) * 1 ether);
    }

    function testVaultCEnds() public {

        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            Total rewards accrued by vaultC
             startTime = 7, endTime = 2,592,007 (30 days)
             
             t7 - t8:  1e18 * 100/180 = 5.555e17                       (vaultC created at t7: no stake, calc based on baseVaultAllocPoints)
             --------------------------------------------------------------------------------------------------------------------------------
             t8 - t9:  1e18 * 40/120 = 3.333e17                        (userC stakes 40 ether at t8)
             t9 - t10: 1e18 * 80/160 = 5e17                            (userC stakes again at t9)
             t10 - t2,592,002: 2,591,992 e18 * 80/160 = 1.2959e24      (rewards split btw vaultA and C)
             t2,592,002 - t2,592,007: 5e18                             (all rewards goes to vaultC)

            Total Rewards: 
             3.333e17 + 5e17 + 1.2959e24 + 5e18     (bonusBall has no fees)
             = 1.2959063888 × 10^24
             ~ 1.296e24

            Total Fees:
              totalRewards * feeFactor = 1.296e24 * 0.2 = 2.592e23
              accCreatorFee = 1.296e24 * 0.1 = 1.296e23
              totalAccRewards = 1.296e24 * 0.1 = 1.296e23
             
            Calculating rewardsAccPerToken:           
             totalRewards = ~ 1.2959e24
             totalRewardsLessFees = ~ 1.0367e24

             [t7 - t10]: 
             rewardsAccPerToken = ~ 1.1666e16

             [t10 - t2_592_007]
             rewardsAccPerToken += incomingRewards - fees / 80e18 
                                 = [(1.2959e24 + 5e18) * 0.8] * 1e18 / 80e18  
                                 = ~ 1.295905 e22

             rewardsAccPerToken = 1.1666e16 + 1.295905e22
                                = 1.2959061666×10^22
                                = ~ 1.295e22     
            ClaimedRewards:
             user claimed rewards at t10
             rewardsClaimed: 5.555e17 + 0.8(3.333e17 + 5e17) = ~ 1.222e18
        */

        assertEq(vaultC.allocPoints, 0);
        assertEq(vaultC.stakedTokens, 0); 
       
        // indexes: in-line with poolIndex
        assertEq(vaultC.accounting.vaultIndex/1e18, 1.62e22/1e18);  
        assertEq(vaultC.accounting.vaultNftIndex, 0); 
        assertEq(vaultC.accounting.rewardsAccPerToken/1e19, 1.295e22/1e19);  

        // rewards (from t=3 to t=4)
        assertEq(vaultC.accounting.totalAccRewards/1e21, 1.295e24/1e21);               
        assertEq(vaultC.accounting.accNftStakingRewards/1e20, 1.295e23/1e20);               // tokens staked. rewards accrued for 1st staker.
        assertEq(vaultC.accounting.accCreatorRewards/1e20, 1.295e23/1e20);                // no tokens staked prior to t=3. therefore no creator rewards       
        assertEq(vaultC.accounting.bonusBall/1e14, 5.555e17/1e14); 
        
        assertEq(vaultC.accounting.totalClaimedRewards/1e15, 1.222e18/1e15);                   //userA: 6.48e23, userB: 3e17, creatorFee: 3e17

        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));
    } 

    // claimFees + claimRewards
    function testUserCVaultCEnds() public {
        
        vm.startPrank(userC);
        stakingPool.claimFees(vaultIdC, userC);
        stakingPool.claimRewards(vaultIdC, userC);
        vm.stopPrank();

        DataTypes.UserInfo memory userCInfo = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);
        
        /**
            userIndex & rewardsAccPerToken
             1.62e22 * (1 - feeFactor) = 1.62e22 * 0.8 = ~ 1.295e22 

            Rewards: accStakingRewards + claimedRewards
             userC should have accrued all the rewards from vaultC
             5.555e17 + (1.296e24 * 0.8) = 1.0368e24
            
            Fees:
             (1.296e24 * 0.2) = 2.592e23

            Total Token balance:
             1.0368e24 + 2.592e23 = 1.296e24


            accCreatorFee = 1.296e24 * 0.1 = 1.296e23

        */

        assertEq(userCInfo.stakedTokens, 0);

        assertEq(userCInfo.userIndex/1e19,  1.295e22/1e19);                
        assertEq(userCInfo.userNftIndex, 0);
        assertEq(userCInfo.userIndex,  vaultC.accounting.rewardsAccPerToken);

        // accStakingRewards == claimed 
        assertEq(userCInfo.accStakingRewards, userCInfo.claimedStakingRewards);    

        assertEq(userCInfo.accStakingRewards/1e21, 1.036e24/1e21);           
        assertEq(userCInfo.claimedStakingRewards/1e21, 1.036e24/1e21);      

        assertEq(userCInfo.accNftStakingRewards, 0);
        assertEq(userCInfo.claimedNftRewards, 0);
        assertEq(userCInfo.claimedCreatorRewards/1e20, 1.295e23/1e20);       

        // check token balance
        uint256 rewardsFeesAndBonusBall = vaultC.accounting.totalClaimedRewards;
        assertEq(mocaToken.balanceOf(userC), vaultC.accounting.totalClaimedRewards + userCPrinciple);


        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));
    }

}
