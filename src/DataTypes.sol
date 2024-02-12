// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract DataTypes {

    /*//////////////////////////////////////////////////////////////
                                  POOL
    //////////////////////////////////////////////////////////////*/

    struct PoolAccounting {
    // rewards: x
    uint256 totalAllocPoints;                // totalBalanceBoosted
    uint256 emissisonPerSecond;           
  
    // rewards: y
    uint256 poolIndex;                       // rewardsAccPerAllocPoint (to date) || rewards are booked into index
    uint256 poolLastUpdateTimeStamp;  
    
    // for updating emissions
    uint256 totalPoolRewards;                // prevent ddos rewards 
    uint256 totalPoolRewardsEmitted;         // prevent ddos rewards vault
    }

    /*//////////////////////////////////////////////////////////////
                                 VAULT
    //////////////////////////////////////////////////////////////*/

    enum VaultDuration{
        NONE,       //0
        THIRTY,     //1
        SIXTY,      //2 
        NINETY      //3
    }

    struct Vault {
        bytes32 vaultId;   
        address creator;

        VaultDuration duration;      // uint8
        uint256 endTime;             // uint40
        
        uint256 multiplier;
        uint256 allocPoints; 

        // staked assets
        uint256 stakedNfts;            //2^8 -1 NFTs
        uint256 stakedTokens;

        VaultAccounting accounting;
    }

    struct VaultAccounting{
        // index
        uint256 vaultIndex;    
        uint256 vaultNftIndex;    //rewardsAccPerNFT
        
        // fees: pct values, with 18dp precision
        uint256 totalFees;   
        uint256 creatorFee;   
        uint256 totalNftFee;       
            
        // rewards
        uint256 totalAccRewards;
        uint256 accNftBoostRewards;
        uint256 accCreatorRewards;    
        uint256 bonusBall;

        uint256 claimedRewards;
    }


    /*//////////////////////////////////////////////////////////////
                                  USER
    //////////////////////////////////////////////////////////////*/

    struct UserInfo {
        bytes32 vaultId;    

        // staked assets
        uint256 stakedNfts;            //2^8 -1 NFTs
        uint256 stakedTokens;
        uint256 allocPoints; 

        // indexes
        uint256 userIndex; 
        uint256 userNftIndex;

        //rewards: tokens
        uint256 accRewards;
        uint256 claimedRewards;

        //rewards: NFTs
        uint256 accNftBoostRewards; 
        uint256 claimedNftRewards;

        //rewards: creatorFees
        uint256 claimedCreatorRewards;
    }
}

// Note: could I do something with vault.lastUpdateTimestamp wrt to updatingUserIndex?
