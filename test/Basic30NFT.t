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

    uint256 public constant nftMultiplier = 2;
    uint256 public constant vault60Multiplier = 2;
    uint256 public constant vault90Multiplier = 3;
    uint256 public constant vaultBaseAllocPoints = 100 ether;     // need 18 dp precision for pool index calc

    // testing data
    address public userA;
    address public userB;
    address public userC;
   
    uint256 public userAPrinciple;
    uint256 public userBPrinciple;
    uint256 public userCPrinciple;

    uint256 public constant userANfts = 1;
    uint256 public constant userBNfts = 1;
    uint256 public constant userCNfts = 2;

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
        nftRegistry.mint(userA, userANfts);
        nftRegistry.mint(userB, userBNfts);
        nftRegistry.mint(userC, userCNfts);

        vm.stopPrank();


        // approvals for receiving Moca tokens for staking
        vm.prank(userA);
        mocaToken.approve(address(stakingPool), userAPrinciple);

        vm.prank(userB);
        mocaToken.approve(address(stakingPool), userBPrinciple);

        vm.prank(userC);
        mocaToken.approve(address(stakingPool), userCPrinciple);
        
        // approval for issuing reward tokens to stakers
        vm.prank(address(rewardsVault));
        mocaToken.approve(address(stakingPool), rewards);

        // approvals for receiving bridgedNFTOKENS for staking
        vm.prank(userA);
        nftRegistry.approve(address(stakingPool), 1);

        vm.prank(userB);
        nftRegistry.approve(address(stakingPool), 1);

        vm.prank(userC);
        nftRegistry.approve(address(stakingPool), 2);


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
//      userA stakes an nft token into VaultA. 
//      vault multiplier increases; so should allocPoints.
//      rewards emitted frm t=3 to t-4 is allocated to userA only.
//      account for bonusBall, 1st NFT incentive, and token staking rewards
abstract contract StateT04 is StateT03 {
    // 
    function setUp() public virtual override {
        super.setUp();

        vm.warp(4);

        vm.prank(userA);
        stakingPool.stakeNfts(vaultIdA, userA, userANfts);
    }
}

contract StateT04Test is StateT04 {

    function testPoolT04() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

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

            
            multplier = 3
            pool.aLLocPoints = 3 * 50e18 = 150e18 
            
        */

        assertEq(pool.totalAllocPoints, (userAPrinciple * vaultA.multiplier)); 
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex, 3e16);
        assertEq(pool.poolLastUpdateTimeStamp, 4);  

        assertEq(pool.totalPoolRewardsEmitted, 2 ether);
    }

    function testVaultAT04() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            userA has staked into vaultA @t=3.
            rewards emitted from t3 to t4, allocated to userA.
             
            rewards & fees:
             incomingRewards = 1e18
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17

             totalAccRewards += incomingRewards = 1e18 + incomingRewards = 1e18 + 1e18 = 2e18
            
             rewardsAccPerToken += incomingRewards - fees / stakedTokens = (1e18 - 2e17)*1e18 / 50e18 = 1.6e16

            multplier = 3
            vault.aLLocPoints = 3 * 50e18 = 150e18 

        */
       
        // nft section 
        assertEq(vaultA.stakedNfts, 1); 
        assertEq(vaultA.multiplier, 3);
        assertEq(vaultA.accounting.vaultNftIndex, 0);       //no nft staked before: so index 0

        // tokens
        assertEq(vaultA.stakedTokens, userAPrinciple); 
        assertEq(vaultA.allocPoints, userAPrinciple * vaultA.multiplier);

        // token index
        assertEq(vaultA.accounting.vaultIndex, 3e16); 
        assertEq(vaultA.accounting.rewardsAccPerToken, 1.6e16); 

        // rewards 
        assertEq(vaultA.accounting.totalAccRewards, 2e18);               
        assertEq(vaultA.accounting.accNftStakingRewards, 1e17);               // tokens staked. rewards accrued for 1st NFT staker.
        assertEq(vaultA.accounting.accCreatorRewards, 1e17);                      
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 0); 
    }

    function testUserAT04() public {

        DataTypes.UserInfo memory userA = getUserInfoStruct(vaultIdA, userA);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            userIndex = vault.accounting.rewardsAccPerToken

            accStakingRewards = bonusBall(t2-t3) + 1e18(t3-t4) 
                       = 1e18 + [1e18 * 0.8]
                       = 1.8e18

            accNftStakingRewards = 1st NFt staking incentive(t3-t4)
                                 = [1e18 * 0.1]
                                 = 1e17
        */

        // nft section 
        assertEq(userA.stakedNfts, 1); 
        assertEq(userA.userNftIndex, 0);

        // tokens
        assertEq(userA.stakedTokens, userAPrinciple);
        assertEq(userA.userIndex, vaultA.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userA.accStakingRewards, 1.8 ether);  // 1e18: bonusBall received + rewards less of fees
        assertEq(userA.claimedStakingRewards, 0);

        assertEq(userA.accNftStakingRewards, 1e17);
        assertEq(userA.claimedNftRewards, 0);

        assertEq(userA.claimedCreatorRewards, 0);
    }
}

//Note: t=05  
//      userB stakes tokens into VaultA.
//      userB should enjoy a multiplier effect from prior staked NFT - reflected in allocPoints
//      rewards emitted frm t-4 to t-5 is allocated to userA only.
abstract contract StateT05 is StateT04 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(5);

        vm.prank(userB);
        stakingPool.stakeNfts(vaultIdA, userB, userBNfts);
    }
}


contract StateT05Test is StateT05 {

    function testPoolT05() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=4 to t=5, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / userAPrinciple * multplier
                                      = 1e18 / (50e18 * 3)
                                      = 6.6666e15
             - poolIndex should therefore be updated to 3e16 + 6.6666e15 = 3.6666e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 3e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 150e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 150e18 ) + 3e16 = 6.6666e15 + 3e16 = 3.6666e16
        */

        assertEq(pool.totalAllocPoints, userAPrinciple * 5);         // additional nft, multiplier: 3 -> 5
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 3.666e16/1e13);                 //rounding: recurring decimal
        assertEq(pool.poolLastUpdateTimeStamp, 5);  

        assertEq(pool.totalPoolRewardsEmitted, 3 ether);
    }

    function testVaultAT05() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            userA has staked into vaultA @t=3.
            userB staked at t5, does not accrue any rewards yet.

            rewards emitted from t4 to t5, allocated to userA.
             
            rewards & fees:
             incomingRewards = 1e18
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17
             accNftStakingRewards = 1e18 * 0.1e18 / precision = 1e17

            totalAccRewards += incomingRewards = 1e18 + incomingRewards = 1e18 + 1e18 = 3e18
            accCreatorFee = 1e17 + 1e17 = 2e17
            accNftStakingRewards = 1e17 + 1e17 = 2e17

            rewardsAccPerToken += incomingRewards - fees / stakedTokens = (1e18 - 2e17) * 1e18 / 50e18 = 1.6e16
             rewardsAccPerToken = 1.6e16 + 1.6e16 = 3.2e16

            vaultNftIndex [t4-t5]: nft staked at t4
             nftIndex += (accTotalNFTFee / vault.stakedNfts)
             nftIndex = (1e17 / 1)
                      = 1e17

            !!!
            poolIndex = vaultIndex = 3.6666e16 
             -> recurring decimal, source of rounding issues within rewards, fee calcs and nftIndex.
        */
       

        // nft section 
        assertEq(vaultA.stakedNfts, 2); 
        assertEq(vaultA.multiplier, 5);
        assertEq(vaultA.accounting.vaultNftIndex/1e13, 9.999e16/1e13);      // calculated val: 1e17 

        // tokens
        assertEq(vaultA.stakedTokens, userAPrinciple); 
        assertEq(vaultA.allocPoints, userAPrinciple * vaultA.multiplier);

        // token index
        assertEq(vaultA.accounting.vaultIndex/1e13, 3.666e16/1e13); 
        assertEq(vaultA.accounting.rewardsAccPerToken/1e13, 3.199e16/1e13);         // calculated val: 3.2e16

        // rewards 
        assertEq(vaultA.accounting.totalAccRewards/1e15, 2.999e18/1e15);                 // calculated: 3e18
        assertEq(vaultA.accounting.accNftStakingRewards/1e14, 1.999e17/1e14);            // calculated val: 2e17
        assertEq(vaultA.accounting.accCreatorRewards/1e14, 1.999e17/1e14);               // calculated val: 2e17       
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 0); 
    }

    function testUserBT05() public {

        DataTypes.UserInfo memory userB = getUserInfoStruct(vaultIdA, userB);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        // userA is not updated! check userB!

        /**
            userIndex = vault.accounting.rewardsAccPerToken

            userNftIndex = vaultA.accounting.vaultNftIndex

            accStakingRewards = bonusBall(t2-t3) + 1e18(t3-t4) + 1e18(t4-t5)  | [bonusBall + rewards less of fees]
                       = 1e18 + [2e18 * 0.8]
                       = 2.6e18

            accNftStakingRewards = 1e17 + [1e18 * 0.2]                 | 1st NFT staker incentive + nft fee
                                 = 3e17
        */

        // nft section 
        assertEq(userB.stakedNfts, 1); 
        assertEq(userB.userNftIndex, vaultA.accounting.vaultNftIndex);

        // tokens
        assertEq(userB.stakedTokens, 0);
        assertEq(userB.userIndex, vaultA.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userB.accStakingRewards, 0 ether);  
        assertEq(userB.claimedStakingRewards, 0);

        assertEq(userB.accNftStakingRewards, 0);
        assertEq(userB.claimedNftRewards, 0);

        assertEq(userB.claimedCreatorRewards, 0);
    }
}

//Note: t=06
//      userB stakes an nft into VaultA.
//      vaultA allocPoints will increase. 
//      rewards emitted frm t-5 to t-6 is allocated to userA and userB.
abstract contract StateT06 is StateT05 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(6);

        vm.prank(userB);
        stakingPool.stakeTokens(vaultIdA, userB, userBPrinciple);
    }
}

contract StateT06Test is StateT06 {

    function testPoolT06() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=5 to t=6, Pool emits 1e18 rewards
            There is only 1 vault in existence, which receives the full 1e18 of rewards
             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / userAPrinciple * multiplier
                                      = 1e18 / (50e18 * 5)
                                      = 4e15
             - poolIndex should therefore be updated to 3.6666e16 + 4e15 = 4.0666e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 3.6666e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 240e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 240e18 ) + 3.6666e16 = 4e15 +  3.6666e16 = 4.0666e16
        */

        assertEq(pool.totalAllocPoints, (userAPrinciple + userBPrinciple) * 5);     // additional nft, multiplier: 3 -> 5
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 4.066e16/1e13);                 //rounding: recurring decimal
        assertEq(pool.poolLastUpdateTimeStamp, 6);  

        assertEq(pool.totalPoolRewardsEmitted, 4 ether);
    }

    function testVaultAT06() public {

        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            t3: userA stakes tokens
            t6: userB stakes tokens

            rewards emitted from t5 to t6, allocated to user A
             
            rewards & fees: [begin to accrue from t3]
             incomingRewards = 1e18
             accCreatorFee = 1e18 * 0.1e18 / precision = 1e17
             accNftStakingRewards = 1e18 * 0.1e18 / precision = 1e17
            

            totalAccRewards += incomingRewards = 1e18 + incomingRewards = 1e18 + 2.999e18 = 3.999e18
             accCreatorFee = 1.999e17 + 1e17 = 2.999e17
             accNftStakingRewards = 1.999e17 + 1e17 = 2.999e17

            rewardsAccPerToken += incomingRewards - fees / stakedTokens = (1e18 - 2e17) * 1e18 / 50e18 = 1.6e16
            rewardsAccPerToken = 3.199e16 + 1.6e16 = 4.799e16

            vaultNftIndex 
             nftIndex += (accTotalNFTFee / vault.stakedNfts)
             nftIndex = (1e17 / 2) + 9.999e16
                      = 1.499e17

            !!!
            poolIndex = vaultIndex = 4.6666e16 
             -> recurring decimal, source of rounding issues within rewards, fee calcs and nftIndex.
        */
       

        // nft section 
        assertEq(vaultA.stakedNfts, 2); 
        assertEq(vaultA.multiplier, 2 + 3);
        assertEq(vaultA.accounting.vaultNftIndex/1e14, 1.499e17/1e14);      

        // tokens
        assertEq(vaultA.stakedTokens, (userAPrinciple + userBPrinciple)); 
        assertEq(vaultA.allocPoints, (userAPrinciple + userBPrinciple) * vaultA.multiplier);
        assertEq(vaultA.allocPoints, (userAPrinciple + userBPrinciple) * 5);

        // token index
        assertEq(vaultA.accounting.vaultIndex/1e13, 4.066e16/1e13); 
        assertEq(vaultA.accounting.rewardsAccPerToken/1e13, 4.799e16/1e13);         // calculated val: 3.2e16

        // rewards 
        assertEq(vaultA.accounting.totalAccRewards/1e15, 3.999e18/1e15);                 
        assertEq(vaultA.accounting.accNftStakingRewards/1e14, 2.999e17/1e14);            
        assertEq(vaultA.accounting.accCreatorRewards/1e14, 2.999e17/1e14);                  
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards, 0); 
    }

    function testUserBT06() public {

        DataTypes.UserInfo memory userB = getUserInfoStruct(vaultIdA, userB);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);


        /**
            userIndex = vault.accounting.rewardsAccPerToken

            userNftIndex = vaultA.accounting.vaultNftIndex

            accStakingRewards = 0 || just staked tokens

            accNftStakingRewards = nftFeeForPeriod / totalStakedNfts 
                                 = 1e17 / 2
                                 = 5e16
        */

        // nft section 
        assertEq(userB.stakedNfts, 1); 
        assertEq(userB.userNftIndex, vaultA.accounting.vaultNftIndex);

        // tokens
        assertEq(userB.stakedTokens, userBPrinciple);
        assertEq(userB.userIndex, vaultA.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userB.accStakingRewards, 0 ether);  
        assertEq(userB.claimedStakingRewards, 0);

        assertEq(userB.accNftStakingRewards, 5e16);
        assertEq(userB.claimedNftRewards, 0);

        assertEq(userB.claimedCreatorRewards, 0);
    }
 
}


//Note: t=07
//      userC creates vaultC
//      pool allocPoints will increase. 
//      rewards emitted frm t6 to t7 is allocated to userA and userB.
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
                                      = 1e18 / (userAPrinciple + userBPrinciple) * multiplier
                                      = 1e18 / (80e18 * 5)
                                      = 2.5e15
             - poolIndex should therefore be updated to 4.0666e16 + 2.5e15 = 4.466e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 4.0666e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 400e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 400e18 ) + 4.0666e16 = 2.5e15 + 4.0666e16 = 4.3166e16

            TotalAllocPoints, updated:
             vaultA + vaultC = [(userAPrinciple + userBPrinciple) * multiplier] + 100e18
        */

        assertEq(pool.totalAllocPoints, (userAPrinciple + userBPrinciple) * 5 + vaultBaseAllocPoints);    
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 4.316e16/1e13);                 //rounding: recurring decimal
        assertEq(pool.poolLastUpdateTimeStamp, 7);  

        assertEq(pool.totalPoolRewardsEmitted, 5 ether);
    }

    function testVaultCT07() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            new vault.
            everything 0.

            multiper = 1.
            vaultIndex == poolIndex

        */
       

        // nft section 
        assertEq(vaultC.stakedNfts, 0); 
        assertEq(vaultC.multiplier, 1);
        assertEq(vaultC.accounting.vaultNftIndex, 0);      

        // tokens
        assertEq(vaultC.stakedTokens, 0); 
        assertEq(vaultC.allocPoints, (vaultBaseAllocPoints) * vaultC.multiplier);
        
        // token index
        assertEq(vaultC.accounting.vaultIndex, pool.poolIndex); // must track poolIndex
        assertEq(vaultC.accounting.rewardsAccPerToken, 0);         

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards, 0);                 
        assertEq(vaultC.accounting.accNftStakingRewards, 0);            
        assertEq(vaultC.accounting.accCreatorRewards, 0);                  
        assertEq(vaultC.accounting.bonusBall, 0); 

        assertEq(vaultC.accounting.totalClaimedRewards, 0); 
    }

    function testUserCT07() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);


        /**
            userIndex = vault.accounting.rewardsAccPerToken

            userNftIndex = vaultA.accounting.vaultNftIndex

            accStakingRewards = 0 || just staked tokens

            accNftStakingRewards = nftFeeForPeriod / totalStakedNfts 
                                 = 1e17 / 2
                                 = 5e16
        */

        // nft section 
        assertEq(userC.stakedNfts, 0); 
        assertEq(userC.userNftIndex, vaultC.accounting.vaultNftIndex);

        // tokens
        assertEq(userC.stakedTokens, 0);
        assertEq(userC.userIndex, vaultC.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userC.accStakingRewards, 0 ether);  
        assertEq(userC.claimedStakingRewards, 0);

        assertEq(userC.accNftStakingRewards, 0);
        assertEq(userC.claimedNftRewards, 0);

        assertEq(userC.claimedCreatorRewards, 0);

    }
}


//Note: t=08
//      userC stakes NFT into vaultC
//      vaultC has no tokens staked, therefore no rewards should be accrued to the NFT.
//      rewards emitted frm t7 to t8 is proportionally split btw both vaults. 
abstract contract StateT08 is StateT07 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(8);

        // create vault
        vm.prank(userC);       
        stakingPool.stakeNfts(vaultIdC, userC, 1);
    }
}


contract StateT08Test is StateT08 {
    
    function testPoolT08() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=7 to t=8, Pool emits 1e18 rewards
            There are 2 vaults in existence; rewards are split.
             totalAllocPoints = [(userAPrinciple + userBPrinciple) * multiplier] + vaultBaseAllocPoints
                              = (80e18 * 5) + 100e18
                              = 5e20

             - rewardsAccruedPerToken = 1e18 / totalAllocPoints 
                                      = 1e18 / 5e20
                                      = 2e15

             - poolIndex should therefore be updated to 4.316e16 + 2e15 = 4.516e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 4.316e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 500e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 500e18 ) + 4.316e16 = 2e15 + 4.316e16 = 4.516e16

            TotalAllocPoints, updated:
             vaultA + vaultC = [(userAPrinciple + userBPrinciple) * multiplier] + 100e18
        */

        assertEq(pool.totalAllocPoints, (userAPrinciple + userBPrinciple) * 5 + vaultBaseAllocPoints);    
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 4.516e16/1e13);                 //rounding: recurring decimal 4.516e16
        assertEq(pool.poolLastUpdateTimeStamp, 8);  

        assertEq(pool.totalPoolRewardsEmitted, 6 ether);
    }

    function testVaultCT08() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            rewards emitted from t7 to t8, allocated to both vaults.
             vaultC's proportion = 100e18 / 5e20

            rewards & fees: 
             [perUnitTime]
             incomingRewards = 1e18 * 100e18 / 5e20 = 2e17
             accCreatorFee = 0
             accNftStakingRewards = 0
             
             [total]
             accCreatorFee = 0
             accNftStakingRewards = 0
             totalAccRewards =  2e17
             bonusBall = 2e17
            
            rewards are booked as bonusBall as no tokens are staked.
        */
       

        // nft section 
        assertEq(vaultC.stakedNfts, 1); 
        assertEq(vaultC.multiplier, 1 + 2);     //nft staked
        assertEq(vaultC.accounting.vaultNftIndex, 0);      

        // tokens
        assertEq(vaultC.stakedTokens, 0); 
        assertEq(vaultC.allocPoints, vaultBaseAllocPoints);
        
        // token index
        assertEq(vaultC.accounting.vaultIndex, pool.poolIndex); // must track poolIndex
        assertEq(vaultC.accounting.rewardsAccPerToken, 0);         

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards, 2e17);                 
        assertEq(vaultC.accounting.accNftStakingRewards, 0);            
        assertEq(vaultC.accounting.accCreatorRewards,  0);                  
        assertEq(vaultC.accounting.bonusBall,  2e17); 

        assertEq(vaultC.accounting.totalClaimedRewards, 0); 
    }

    function testUserCT08() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);


        /**
            userIndex = vault.accounting.rewardsAccPerToken

            userNftIndex = vaultA.accounting.vaultNftIndex

            accStakingRewards = 0 || no tokens staked

            accNftStakingRewards = nftFeeForPeriod / totalStakedNfts 
                                 = 0
                        
        */

        // nft section 
        assertEq(userC.stakedNfts, 1); 
        assertEq(userC.userNftIndex, vaultC.accounting.vaultNftIndex);

        // tokens
        assertEq(userC.stakedTokens, 0);
        assertEq(userC.userIndex, vaultC.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userC.accStakingRewards, 0 ether);  
        assertEq(userC.claimedStakingRewards, 0);

        assertEq(userC.accNftStakingRewards, 0);
        assertEq(userC.claimedNftRewards, 0);

        assertEq(userC.claimedCreatorRewards, 0);

    }
}


//Note: t=09
//      userC stakes tokens into vaultC
//      rewards emitted frm t8 to t9 is proportionally split btw both vaults. 
//      creator/nft fees are not applied to rewards as no tokens have been staked in prior periods
//      since the 1st token stake into the vault occurs, userC is the beneficary of the bonusBall payout
//      bonusBall is booked to userC - accStakingRewards
abstract contract StateT09 is StateT08 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(9);

        // create vault
        vm.prank(userC);       
        stakingPool.stakeTokens(vaultIdC, userC, userCPrinciple);
    }
}

contract StateT09Test is StateT09 {

    function testPoolT09() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=8 to t=9, Pool emits 1e18 rewards
            There are 2 vaults in existence; rewards are split.
             totalAllocPoints = [(userAPrinciple + userBPrinciple) * multiplier] + vaultBaseAllocPoints
                              = (80e18 * 5) + 100e18
                              = 5e20

             - rewardsAccruedPerAllocPoint = 1e18 / totalAllocPoints 
                                           = 1e18 / 5e20
                                           = 2e15

             - poolIndex should therefore be updated to 4.516e16 + 2e15 = 4.716e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 4.516e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 500e18
            
            - poolIndex = (1e18 * 1 * 1e18 / 500e18 ) + 4.516e16 = 2e15 + 4.516e16 = 4.716e16

            TotalAllocPoints, updated:
             vaultA + vaultC = [(userAPrinciple + userBPrinciple) * multiplier] + 100e18
        */

        // vaultC multiplier: 3, from prior Nft staked
        assertEq(pool.totalAllocPoints, ((userAPrinciple + userBPrinciple) * 5) + (userCPrinciple * 3));    
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 4.716e16/1e13);                 //rounding: recurring decimal 4.516e16
        assertEq(pool.poolLastUpdateTimeStamp, 9);  

        assertEq(pool.totalPoolRewardsEmitted, 7 ether);
    }

    function testVaultCT09() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            rewards emitted from t8 to t9, allocated to both vaults.
             vaultC's proportion = 100e18 / 5e20

            rewards & fees: **no tokens, so no fees**
             [perUnitTime]
             incomingRewards = 1e18 * 100e18 / 5e20 = 2e17
             accCreatorFee = 0
             accNftStakingRewards = 0
             
             [total]
             accCreatorFee = 0
             accNftStakingRewards = 0
             totalAccRewards =  2e17 + 2e17 = 4e17
             bonusBall = 2e17 + 2e17 = 4e17    
              * rewards are booked as bonusBall as no tokens are staked.
            
            nftIndex = 0; 
             nftIndex starts tracking, once tokens are staked.
             as nftFee is only levied on vaults with tokens staked.

        */
       

        // nft section 
        assertEq(vaultC.stakedNfts, 1); 
        assertEq(vaultC.multiplier, 1 + 2);                      // nft staked
        assertEq(vaultC.accounting.vaultNftIndex, 0);            // nftIndex only increments once there are stakedTokens    

        // tokens
        assertEq(vaultC.stakedTokens, userCPrinciple); 
        assertEq(vaultC.allocPoints, (userCPrinciple * 3));
        
        // token index
        assertEq(vaultC.accounting.vaultIndex, pool.poolIndex); // must track poolIndex
        assertEq(vaultC.accounting.rewardsAccPerToken, 0);         

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards, 4e17);                 
        assertEq(vaultC.accounting.accNftStakingRewards, 0);            
        assertEq(vaultC.accounting.accCreatorRewards,  0);                  
        assertEq(vaultC.accounting.bonusBall,  4e17); 

        assertEq(vaultC.accounting.totalClaimedRewards, 0); 
    }
    
    function testUserCT09() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);


        /**
            userIndex = vault.accounting.rewardsAccPerToken

            userNftIndex = vaultA.accounting.vaultNftIndex

            accStakingRewards = 0 || no tokens staked

            accNftStakingRewards = nftFeeForPeriod / totalStakedNfts 
                                 = 0
                        
        */

        // nft section 
        assertEq(userC.stakedNfts, 1); 
        assertEq(userC.userNftIndex, vaultC.accounting.vaultNftIndex);

        // tokens
        assertEq(userC.stakedTokens, userCPrinciple);
        assertEq(userC.userIndex, vaultC.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userC.accStakingRewards, 4e17);  
        assertEq(userC.claimedStakingRewards, 0);

        assertEq(userC.accNftStakingRewards, 0);
        assertEq(userC.claimedNftRewards, 0);

        assertEq(userC.claimedCreatorRewards, 0);
    }   
}


//Note: t=10
//      no user action is taken.
//      vaultC state is updated to reflect state at t10. 
//      now that the vault contains tokens, allocPOints should be udpated.
//      we check if the fees and rewards have been correctly calculated.
//      rewards emitted frm t9 to t10 is proportionally split btw both vaults. 
abstract contract StateT10 is StateT09 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(10);

        vm.prank(userC);       
        stakingPool.updateVault(vaultIdC);
    }
}


contract StateT10Test is StateT10 {

    function testPoolT10() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=9 to t=10, Pool emits 1e18 rewards
            There are 2 vaults in existence; rewards are split.
             totalAllocPoints = [(userAPrinciple + userBPrinciple) * multiplier] + [userCPrincple * multiplier]
                              = (80e18 * 5) + (80e18 * 3)
                              = 6.4e20

             - rewardsAccruedPerAllocPoint = 1e18 / totalAllocPoints 
                                           = 1e18 / 6.4e20
                                           = 1.562e15

             - poolIndex should therefore be updated to 4.716e16 + 1.562e15 = 4.872e16 (index represents rewardsPerToken since inception)

            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 4.716e16
             - timeDelta: 1 seconds 
             - totalAllocPoints: 6.4e20
            
            - poolIndex = (1e18 * 1 * 1e18 / 6.4e20 ) + 4.716e16 = 1.562e15 + 4.516e16 = 4.872e16 

        */

        // vaultC multiplier: 3, from prior Nft staked
        assertEq(pool.totalAllocPoints, ((userAPrinciple + userBPrinciple) * 5) + (userCPrinciple * 3));    
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e13, 4.872e16/1e13);                 //rounding: recurring decimal 4.516e16
        assertEq(pool.poolLastUpdateTimeStamp, 10);  

        assertEq(pool.totalPoolRewardsEmitted, 8 ether);
    }

    function testVaultCT10() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**
            rewards emitted from t9 to t10, allocated to both vaults.
             vaultC's proportion = (80e18 * 3) / 6.4e20
                                 = 2.4e20 / 6.4e20

            rewards & fees: 
             [perUnitTime]
             incomingRewards = 1e18 * 2.4e20 / 6.4e20 = 3.75e17
             accCreatorFee = 3.75e17 * 0.1 = 3.75e16
             accNftStakingRewards = 3.75e17 * 0.1 = 3.75e16
             
             [total]
             accCreatorFee = 3.75e16
             accNftStakingRewards = 3.75e16
             totalAccRewards =  4e17 + 3.75e17 = 7.75e17
             bonusBall = 2e17 + 2e17 = 4e17    
              * rewards are booked as bonusBall as no tokens are staked.
            
            rewardsAccPerToken += incomingRewards * (1 - feeFactor) / stakedTokens = (3.75e17 * 0.8) * 1e18 / 80e18 = 3.75e15
             rewardsAccPerToken = 3.75e15

            vaultNftIndex [t9-t10]: 
             nftIndex += (3.75e16 / vault.stakedNfts)
             nftIndex = (3.75e16 / 1)
                      = 3.75e16
             
             ** nft staked at t8, but tokens only staked at t9

        */
       

        // nft section 
        assertEq(vaultC.stakedNfts, 1); 
        assertEq(vaultC.multiplier, 1 + 2);                            // nft staked
        assertEq(vaultC.accounting.vaultNftIndex, 3.75e16);            // nftIndex only increments once there are stakedTokens    

        // tokens
        assertEq(vaultC.stakedTokens, userCPrinciple); 
        assertEq(vaultC.allocPoints, (userCPrinciple * 3));
        
        // token index
        assertEq(vaultC.accounting.vaultIndex, pool.poolIndex);         // must track poolIndex
        assertEq(vaultC.accounting.rewardsAccPerToken, 3.75e15);         

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards, 7.75e17);                 
        assertEq(vaultC.accounting.accNftStakingRewards, 3.75e16);            
        assertEq(vaultC.accounting.accCreatorRewards,  3.75e16);                  
        assertEq(vaultC.accounting.bonusBall,  4e17); 

        assertEq(vaultC.accounting.totalClaimedRewards, 0); 
    }
    
}

//Note: t=2_592_002 | 2 + 30 days
//      vaultA ends
//      userA and userB claim all rewards, fees and unstake their assets.
//      poolAllocPOints should be decremented; reflecting only vaultC AllocPoints
abstract contract StateVaultAEnds is StateT10 {

    function setUp() public virtual override {
        super.setUp();
        
        uint256 vaultAEnds = 2 + 30 days;
        vm.warp(vaultAEnds);

        stakingPool.unstakeAll(vaultIdA, userA);
        stakingPool.unstakeAll(vaultIdA, userB);

        stakingPool.claimRewards(vaultIdA, userA);
        stakingPool.claimRewards(vaultIdA, userB);

        stakingPool.claimFees(vaultIdA, userB);

        stakingPool.claimFees(vaultIdA, userA);

    }
}

contract StateVaultAEndsTest is StateVaultAEnds {

    function testPoolVaultAEndTime() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**
            From t=10 to t=2_592_002, Pool emits 1e18 * (2_592_002 - 10) rewards
                1e18 * (2_592_002 - 10) = 2.591992e24
            There are 2 vaults in existence; rewards are split.
             totalAllocPoints = [(userAPrinciple + userBPrinciple) * multiplier] + [userCPrincple * multiplier]
                              = (80e18 * 5) + (80e18 * 3)
                              = 6.4e20

             - rewardsAccruedPerAllocPoint = 2.591e24 / totalAllocPoints 
                                           = 2.591992e24 / 6.4e20 
                                           = 4.0499875e21

             - poolIndex should therefore be updated to 4.872e16 + 4.0499875e21 = 4.05003622e21 (index represents rewardsPerToken since inception)
                                                                                ~ 4.050e21
            Calculating index:
            - poolIndex = (eps * timeDelta * precision / totalAllocPoints) + oldIndex
             - eps: 1e18 
             - oldIndex: 4.872e16
             - timeDelta: 2591992 seconds 
             - totalAllocPoints: 6.4e20
            
            - poolIndex = (1e18 * 2591992 * 1e18 / 6.4e20 ) + 4.872e16 
                        = 4.0499875e21 + 4.872e16  
                        = 4.05003266e21
                        ~ 4.050e21

        */

        // vaultC multiplier: 3, from prior Nft staked
        assertEq(pool.totalAllocPoints, (userCPrinciple * 3));    
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e18, 4.050e21/1e18);                
        assertEq(pool.poolLastUpdateTimeStamp, 2_592_002);  

        assertEq(pool.totalPoolRewardsEmitted, 2_592_000 ether);
    }

    function testVaultAHasEnded() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        /**
            t3: userA stakes tokens 
            t6: userB stakes tokens
            
            Total rewards accrued by vaultA
             vaultA lifespan: [t2 - t2_592_002]
             
             t2 - t3: 1e18 (bonusBall)
             t3 - t7: 4e18 (userA stakes at t3)         
             t7 - t8: 1e18 * 400e18 / 500e18 = 8e17         (vaultC created at t7 | allocPoints changes)
             t8 - t9: 1e18 * 400e18 / 500e18 = 8e17         (userC stakes nft at t8 | but no tokens - so no impact on allocPOints)
             t9 - t10: 1e18 * 400e18 / 6.4e20 = 6.25e17     (userC stakes tokens at t9 | allocPoints changes)
             t10 - t2_592_002: 2.591992e24 * 400e18 / 6.4e20 = 1.619995e24

             totalRewards = 1e18 + 4e18 + 8e17+ 8e17 + 6.25e17 + 1.619995e24
                          = 1.620002225e24
                          ~ 1.620e24

             accCreatorFee = 1.620002225e24 * 0.1 = 1.620002225e23 ~ 1.620e23
             accNftStakingRewards = 1.620002225e24 * 0.1 = 1.620002225e23 ~ 1.620e23

            rewardsAccPerToken
             [t6 - t2_592_002]
             incomingRewards: 1e18 + 8e17 + 8e17 + 6.25e17 + 1.619995e24
                            = 1.619998225e24
             incomingRewardsLessOfFees = 1.619998225e24 * 0.8 
                                       = 1.29599858e24
            
             rewardsAccPerToken =  1.29599858e24 / 80e18
                                = 1.619998225e22
             [t3 - t6]
             rewardsAccPerToken =  1.6e16    
            
            rewardsAccPerToken = 1.6e16 + 1.619998225e22 = 1.619999825e22 ~ 1.620e22


            vaultNftIndex
             [t6 - t2_592_002]
             accNftStakingRewards = 1.619998225e24 * 0.1
                                  = 1.619998225e23
             nftIndex = (accTotalNFTFee / vault.stakedNfts)
             nftIndex = (1.619998225e23 / 2) 
                      = 8.099991125e22
             
             t6: nftIndex = 1.499e17
             finaL: nftIndex = 1.499e17 + 8.099991125e22
                             = 8.100006115e22
                             ~ 8.100e22

        */
       

        // nft section 
        assertEq(vaultA.stakedNfts, 0); 
        assertEq(vaultA.multiplier, 5);
        assertEq(vaultA.accounting.vaultNftIndex/1e19, 8.100e22/1e19);      

        // tokens
        assertEq(vaultA.stakedTokens, 0); 
        assertEq(vaultA.allocPoints, 0);
        
        // token index
        assertEq(vaultA.accounting.vaultIndex, pool.poolIndex); 
        assertEq(vaultA.accounting.rewardsAccPerToken/1e19, 1.620e22/1e19);         

        // rewards 
        assertEq(vaultA.accounting.totalAccRewards/1e21, 1.620e24/1e21);                 
        assertEq(vaultA.accounting.accNftStakingRewards/1e20, 1.620e23/1e20);            
        assertEq(vaultA.accounting.accCreatorRewards/1e20, 1.620e23/1e20);                  
        assertEq(vaultA.accounting.bonusBall, 1e18); 

        assertEq(vaultA.accounting.totalClaimedRewards/1e21, 1.620e24/1e21);        
       

        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));
    }

    function testUserAVaultAHasEnded() public {
        DataTypes.UserInfo memory userA = getUserInfoStruct(vaultIdA, userA);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        //user nft incentive" 1e17 | bonusBall: 1e18

        /** UserA is a beneficiary of bonusball of 1st nft staking incentive

            userIndex = vault.accounting.rewardsAccPerToken
            userNftIndex = vaultA.accounting.vaultNftIndex

            rewardsAccPerToken
             [t6 - t2_592_002]
             rewardsAccPerToken: 1e18 + 8e17 + 8e17 + 6.25e17 + 1.619995e24         //ref: Vault breakdown
                               = 1.619998225e22
             rewardsLessOfFees = 1.619998225e22 * 0.8 
                               = 1.29599858e22
            accStakingRewards 
             [t6 - t2_592_002]
             accStakingRewards = rewardsLessOfFees * userBPrinciple
                       = 1.619998225e22 * 50
                       = 8.099991125e23
             [t3 - t6]
             accStakingRewards = 1.8e18
            
             [total]
             accStakingRewards = 1.8e18 + 8.099991125e23 
                       = 8.100009125e23
                       = 8.100e23

            accNftStakingRewards 
             [t6 - t2_592_002]
             accNftStakingRewards = nftFeeForPeriod / totalStakedNfts 
                                 = 1.619998225e23 / 2
                                 = 8.099991125e22
             [t3 - t4]
              accNftStakingRewards = 1e17  (1st NFt staking incentive)
             
             [t4 - t5]
              accNftStakingRewards = 1e18 * 0.1 = 1e17 

             [t5 - t6]
             accNftStakingRewards = 5e16
            
            accNftStakingRewards = 1e7 + 1e17 + 5e16 + 8.099991125e22
                                 = 8.100006125000001e22
                                 ~ 8.100e22
            
            creatorRewards: totalRewards * 0.1 = 1.620e24 * 0.1
             
        */

        // nft section 
        assertEq(userA.stakedNfts, 0); 
        assertEq(userA.userNftIndex, vaultA.accounting.vaultNftIndex);

        // tokens
        assertEq(userA.stakedTokens, 0);
        assertEq(userA.userIndex, vaultA.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userA.accStakingRewards/1e20, 8.100e23/1e20);             
        assertEq(userA.claimedStakingRewards/1e20, 8.100e23/1e20);         

        assertEq(userA.accNftStakingRewards/1e19, 8.100e22/1e19);   
        assertEq(userA.claimedNftRewards/1e19, 8.100e22/1e19);         

        assertEq(userA.claimedCreatorRewards/1e20, 1.62e23/1e20);   

    }

    function testUserBVaultAHasEnded() public {

        DataTypes.UserInfo memory userB = getUserInfoStruct(vaultIdA, userB);
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);


        /** UserB is NOT a beneficiary of either bonusball of 1st nft staking incentive

            userIndex = vault.accounting.rewardsAccPerToken
            userNftIndex = vaultA.accounting.vaultNftIndex

            rewardsAccPerToken
             [t6 - t2_592_002]
             rewardsAccPerToken: 1e18 + 8e17 + 8e17 + 6.25e17 + 1.619995e24
                               = 1.619998225e22
             rewardsLessOfFees = 1.619998225e22 * 0.8 
                               = 1.29599858e22
            
            accStakingRewards = rewardsLessOfFees * userBPrinciple
                       = 1.619998225e22 * 30
                       = 4.859994675e23
                       ~ 4.859e23

            accNftStakingRewards 
             [t6 - t2_592_002]
             accNftStakingRewards = nftFeeForPeriod / totalStakedNfts 
                                 = 1.619998225e23 / 2
                                 = 8.099991125e22
             [t5 - t6]
             accNftStakingRewards = 5e16
            
            accNftStakingRewards = 5e16 + 8.099991125e22 = 8.099996125e22 ~ 8.099e22

        */

        // nft section 
        assertEq(userB.stakedNfts, 0); 
        assertEq(userB.userNftIndex, vaultA.accounting.vaultNftIndex);

        // tokens
        assertEq(userB.stakedTokens, 0);
        assertEq(userB.userIndex, vaultA.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userB.accStakingRewards/1e20, 4.859e23/1e20);             
        assertEq(userB.claimedStakingRewards/1e20, 4.859e23/1e20);         

        assertEq(userB.accNftStakingRewards/1e19, 8.099e22/1e19);   
        assertEq(userB.claimedNftRewards/1e19, 8.099e22/1e19);         

        assertEq(userB.claimedCreatorRewards, 0);
    }

    function testCannotStakeNFTVaultEnded() public {
        vm.prank(userC);

        vm.expectRevert(abi.encodeWithSelector(Errors.VaultMatured.selector, vaultIdA));

        stakingPool.stakeNfts(vaultIdA, userC, 1);
    }

    function testCannotStakeTokensVaultEnded() public {
        vm.prank(userC);
        
        vm.expectRevert(abi.encodeWithSelector(Errors.VaultMatured.selector, vaultIdA));

        stakingPool.stakeTokens(vaultIdA, userA, userAPrinciple);
    }
   
}

//Note: t=2_592_007 | 7 + 30 days
//      vault C ends
//      poolAllocPOints should be decremented to 0.
//      userC claim all rewards, fees and unstake their assets.
abstract contract StateVaultCEnds is StateVaultAEnds {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(7 + 30 days);  // 2592007

        // unstake all - to update all user's states
        stakingPool.unstakeAll(vaultIdC, userC);
        stakingPool.claimRewards(vaultIdC, userC);
        stakingPool.claimFees(vaultIdC, userC);
    }   
}

contract StateVaultCEndsTest is StateVaultCEnds {

    function testPoolVaultCEndTime() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        /**

            At=2_592_002
             - poolIndex = 4.05003622e21 (index represents rewardsPerToken since inception)
                         ~ 4.050e21
            
            From t=2_592_002 to t=2_592_007, Pool emits 5e18 rewards; all to vaultC
             - rewardsAccruedPerAllocPoint = 5e18 / totalAllocPoints 
                                           = 5e18 / (80e18 * 3) 
                                           = 2.083333e16

             - poolIndex should therefore be updated to 4.050e21 + 2.083333e16 = 4.05002083333e21 (index represents rewardsPerToken since inception)
                                                                                ~ 4.050e21
        */

        assertEq(pool.totalAllocPoints, 0);    
        assertEq(pool.emissisonPerSecond, 1 ether);

        assertEq(pool.poolIndex/1e18, 4.050e21/1e18);                
        assertEq(pool.poolLastUpdateTimeStamp, 2_592_007);  

        assertEq(pool.totalPoolRewardsEmitted, 2_592_005 ether);
    }

    function testVaultCHasEnded() public {

        DataTypes.PoolAccounting memory pool = getPoolStruct();
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /**     vaultC lifespan: [t7 - t2_592_007]

            Total rewards accrued by vaultC:             
             t7 - t9: 4e17 (bonusBall)
             t9 - t2_592_002: 2591993e18 * 240e18 / 6.4e20 = 9.71997375e23
             t2_592_002 - t2_592_007: 5e18 

             totalAccRewards = 4e17 + 9.71997375e23 + 5e18
                             = 9.72002775e23
                             ~ 9.720e23

             accCreatorFee = 9.72002775e23 * 0.1 = 9.72002775e22 ~ 9.720e22
             accNftStakingRewards = 9.72002775e23 * 0.1 = 9.72002775e22 ~ 9.720e22

            rewardsAccPerToken: 
             [t9 - t2_592_002]
             incomingRewards: 9.71997375e23 + 5e18 = 9.72002375e23
             incomingRewardsLessOfFees = 9.72002375e23 * 0.8 
                                       = 7.776019e23
            
             rewardsAccPerToken = 7.776019e23 / 80e18
                                = 9.72002375e21
                                ~ 9.720e21

            vaultNftIndex
             [t9 - t2_592_007]
             accNftStakingRewards = 9.720e22
                                  
             nftIndex = (accTotalNFTFee / vault.stakedNfts)
             nftIndex = (9.720e22 / 1) 
                      = 9.720e22

        */
       

        // nft section 
        assertEq(vaultC.stakedNfts, 0); 
        assertEq(vaultC.multiplier, 3);
        assertEq(vaultC.accounting.vaultNftIndex/1e19, 9.720e22/1e19);      

        // tokens
        assertEq(vaultC.stakedTokens, 0); 
        assertEq(vaultC.allocPoints, 0);
        
        // token index
        assertEq(vaultC.accounting.vaultIndex, pool.poolIndex); 
        assertEq(vaultC.accounting.rewardsAccPerToken/1e18, 9.720e21/1e18);         

        // rewards 
        assertEq(vaultC.accounting.totalAccRewards/1e20,  9.720e23/1e20);                 
        assertEq(vaultC.accounting.accNftStakingRewards/1e19, 9.720e22/1e19);            
        assertEq(vaultC.accounting.accCreatorRewards/1e19, 9.720e22/1e19);                  
        assertEq(vaultC.accounting.bonusBall, 4e17); 

        assertEq(vaultC.accounting.totalClaimedRewards/1e20,  9.720e23/1e20);    

        // check vault balances: initial rewards - claimedRewards
        DataTypes.Vault memory vaultA = getVaultStruct(vaultIdA);

        uint256 vaultBalance = mocaToken.balanceOf(address(rewardsVault));
        
        assertEq(vaultBalance, rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));                  
        assertEq(rewardsVault.totalVaultRewards(), rewards - (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

        assertEq(rewardsVault.totalPaidRewards(), (vaultA.accounting.totalClaimedRewards + vaultC.accounting.totalClaimedRewards));

    }

    function testUserCVaultCHasEnded() public {

        DataTypes.UserInfo memory userC = getUserInfoStruct(vaultIdC, userC);
        DataTypes.Vault memory vaultC = getVaultStruct(vaultIdC);

        /** 
            UserC is the sole beneficiary of all of VaultC rewards and fees.
        */

        // nft section 
        assertEq(userC.stakedNfts, 0); 
        assertEq(userC.userNftIndex, vaultC.accounting.vaultNftIndex);

        // tokens
        assertEq(userC.stakedTokens, 0);
        assertEq(userC.userIndex, vaultC.accounting.rewardsAccPerToken);   

        // rewards
        assertEq(userC.accStakingRewards/1e20,     (vaultC.accounting.totalAccRewards * 8/10) /1e20);            
        assertEq(userC.claimedStakingRewards/1e20, (vaultC.accounting.totalAccRewards * 8/10) /1e20);         

        assertEq(userC.accNftStakingRewards, vaultC.accounting.accNftStakingRewards);   
        assertEq(userC.claimedNftRewards, vaultC.accounting.accNftStakingRewards);         

        assertEq(userC.claimedCreatorRewards, vaultC.accounting.accCreatorRewards);     

    }

}