// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2, stdStorage, StdStorage} from "forge-std/Test.sol";

// my contracts
import {MockPool} from "./MockPool.sol";
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
    MockPool public stakingPool;
    RewardsVault public rewardsVault;

    // staking assets
    MocaToken public mocaToken;  
    
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

    // router
    address public router;

//-------------------------------events-------------------------------------------
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

//-----------------------------------------------------------------------------------

    function setUp() public virtual {

        owner = makeAddr("owner");
        router = makeAddr("router");
        
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");

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

        //setup vault
        rewardsVault = new RewardsVault(IERC20(mocaToken), owner, owner);
        mocaToken.mint(owner, rewards);  
        mocaToken.approve(address(rewardsVault), rewards); 
        rewardsVault.deposit(owner, rewards);

        // IERC20 stakedToken, IERC20 rewardToken, address realmPoints, address rewardsVault, address registry,
        // uint256 startTime_, uint256 duration, uint256 rewards
        // string memory name, string memory symbol, address owner
        stakingPool = new MockPool(IERC20(mocaToken), IERC20(mocaToken), address(0), address(rewardsVault), address(0), startTime, duration, rewards, "stkMOCA", "stkMOCA", owner);
        //set router
        stakingPool.setRouter(router);

        rewardsVault.setPool(address(stakingPool));

        //mint tokens to users
        mocaToken.mint(userA, userAPrinciple);
        mocaToken.mint(userB, userBPrinciple);
        mocaToken.mint(userC, userCPrinciple);

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


    function generateVaultId() public view returns (bytes32) {
        uint256 salt = block.number - 1;
        return bytes32(keccak256(abi.encode(msg.sender, block.timestamp, salt)));
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

       stakingPool.createVault(userA, DataTypes.VaultDuration.THIRTY, creatorFee, nftFee);
    }

    function testCannotStake() public {
        vm.prank(userA);

        vm.expectRevert("Not started");
        
        bytes32 vaultId = bytes32(0);
        stakingPool.stakeTokens(vaultId, userA, userAPrinciple);
    }   

    function testEmptyVaults(bytes32 vaultId) public {
        
        DataTypes.Vault memory vault = stakingPool.getVaultStruct(vaultId);

        assertEq(vault.vaultId, bytes32(0));
        assertEq(vault.creator, address(0));   
    }
}
