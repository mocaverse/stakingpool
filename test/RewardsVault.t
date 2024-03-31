// test deposit
// test withdraw
// test recover
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

    address public admin;
    address public moneyManager;

    // stakingPool constructor data
    uint256 public startTime;           
    uint256 public duration;    
    uint256 public rewards;            
    string public name; 
    string public symbol;
    address public owner;
    
    function setUp() public virtual {
        
        rewards = 100 ether;

        vm.startPrank(admin);

        admin = address(0x1111);
        moneyManager = address(0x2222);

        mocaToken = new MocaToken("MocaToken", "MOCA");
        mocaToken.mint(moneyManager, rewards);  

        //setup vault
        rewardsVault = new RewardsVault(IERC20(mocaToken), moneyManager, admin);

        vm.stopPrank();


        // deposit to vault
        vm.startPrank(moneyManager);

        mocaToken.approve(address(rewardsVault), rewards); 
        rewardsVault.deposit(admin, rewards);

        vm.stopPrank();

        vm.startPrank(admin);


        // IERC20 stakedToken, IERC20 lockedNftToken, IERC20 rewardToken, address realmPoints, address rewardsVault, uint128 startTime_, uint128 duration, uint128 rewards, 
        // string memory name, string memory symbol, address owner
        stakingPool = new Pool(IERC20(mocaToken), IERC20(nftRegistry), IERC20(mocaToken), address(0), address(rewardsVault), startTime, duration, rewards, "stkMOCA", "stkMOCA", admin);

        rewardsVault.setPool(address(stakingPool));

        vm.stopPrank();


    }
}


/**
do you want to split constructor in pool to have a setup

 */