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
        uint256 vaultIndex;             //rewardsAccPerAllocPoint
        uint256 vaultNftIndex;          //rewardsAccPerNFT
        uint256 rewardsAccPerToken;

        // fees: pct values, with 18dp precision
        uint256 totalFeeFactor;   
        uint256 creatorFeeFactor;   
        uint256 totalNftFeeFactor;       
            
        // rewards | based on allocPoints
        uint256 totalAccRewards;
        uint256 accNftStakingRewards;
        uint256 accCreatorRewards;    
        uint256 bonusBall;

        // total: staking, nft, creator
        uint256 totalClaimedRewards;    
    }


    /*//////////////////////////////////////////////////////////////
                                  USER
    //////////////////////////////////////////////////////////////*/

    struct UserInfo {

        // staked assets
        uint256 stakedNfts;            
        uint256 stakedTokens;
        // nfts staked: array.length < 4
        uint256[] tokenIds;

        // indexes
        uint256 userIndex; 
        uint256 userNftIndex;

        //rewards: tokens (from staking tokens less of fees)
        uint256 accStakingRewards;
        uint256 claimedStakingRewards;

        //rewards: NFTs
        uint256 accNftStakingRewards; 
        uint256 claimedNftRewards;

        //rewards: creatorFees
        uint256 claimedCreatorRewards;
    }
}

// Note: vaultId not assigned in stakeTokens.
// user B userInfo vaultID is 0.
