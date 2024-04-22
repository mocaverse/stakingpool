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
        uint256 index;                       // rewardsAccPerAllocPoint (to date) || rewards are booked into index
        uint256 lastUpdateTimeStamp;  
        
        // for updating emissions
        uint256 totalStakingRewards;       // total staking rewards for emission
        uint256 rewardsEmitted;            // prevent ddos rewards vault
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
        uint256 stakedTokensLimit;          

        // staked assets
        uint256 stakedNfts;            //2^8 -1 NFTs. uint8
        uint256 stakedTokens;

        VaultAccounting accounting;
    }

    struct VaultAccounting {
        // index
        uint256 vaultIndex;             //rewardsAccPerAllocPoint
        uint256 vaultNftIndex;          //rewardsAccPerNFT

        // fees: pct values, with 18dp precision
        uint256 creatorFeeFactor;   
        uint256 nftFeeFactor;       
            
        // rewards | based on allocPoints
        uint256 totalAccRewards;
        uint256 accNftStakingRewards;
        uint256 accCreatorRewards;    

        uint256 rewardsAccPerToken;
        uint256 totalClaimedRewards;    // total: staking, nft, creator
    }


    /*//////////////////////////////////////////////////////////////
                                  USER
    //////////////////////////////////////////////////////////////*/

    struct UserInfo {

        // staked assets
        uint256[] tokenIds;     // nfts staked: array.length < 4
        uint256 stakedTokens;   

        // indexes
        uint256 userIndex; 
        uint256 userNftIndex;

        //rewards: tokens (from staking tokens less of fees)
        uint256 accStakingRewards;          // receivable      
        uint256 claimedStakingRewards;      // received

        //rewards: NFTs
        uint256 accNftStakingRewards; 
        uint256 claimedNftRewards;

        //rewards: creatorFees
        uint256 claimedCreatorRewards;
    }
}

// Note: vaultId not assigned in stakeTokens.
// user B userInfo vaultID is 0.
