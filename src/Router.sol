// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Errors} from './Errors.sol';
import {DataTypes} from './DataTypes.sol';

import {IPool} from "./interfaces/IPool.sol";
import {IRealmPoints} from "./interfaces/IRealmPoints.sol";
import {RevertMsgExtractor} from "./utils/RevertMsgExtractor.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

//note: inherit forwarder stuff

contract Router {
    using SafeERC20 for IERC20;

    
    IPool public POOL;
    IERC20 public immutable STAKED_TOKEN;  
    IRealmPoints public immutable REALM_POINTS;


// ------- [note: need to confirm values] -------------------
    
    // RP needed to create vaults
    uint256 public constant RP_REQUIRED_VAULT_30 = 600;
    uint256 public constant RP_REQUIRED_VAULT_60 = 500;
    uint256 public constant RP_REQUIRED_VAULT_90 = 400;

    // increments
    uint256 public constant MOCA_INCREMENT_PER_RP = 800 * 1e18;    
    
    // realm points 
    bytes32 public constant season = hex"01"; 
    bytes32 public constant consumeReasonCode = hex"01";

//-------------------------------Events---------------------------------------------

    // events
    event RealmPointsBurnt(uint256 realmId, uint256 rpBurnt);

//------------------------------- constructor -------------------------------------------

    constructor(address mocaToken, address pool, address realmPoints) {
        STAKED_TOKEN = IERC20(mocaToken);
        POOL = IPool(pool);
        REALM_POINTS = IRealmPoints(realmPoints);
    }


    /// @dev Allows batched call to self (this contract).
    /// @param calls An array of inputs for each call.
    function batch(bytes[] calldata calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);

        for (uint256 i; i < calls.length; i++) {

            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
            results[i] = result;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 CREATE
    //////////////////////////////////////////////////////////////*/

    ///@dev Calls createVault
    function createVault(DataTypes.VaultDuration duration, uint256 creatorFeeFactor, uint256 nftFeeFactor, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        
        // burn RP
        uint256 rpRequired = uint8(duration) == 3 ? RP_REQUIRED_VAULT_90 : (uint8(duration) == 2 ? RP_REQUIRED_VAULT_60 : RP_REQUIRED_VAULT_30);
        _checkAndBurnRp(rpRequired, realmId, v, r, s);
        
        // call pool
        POOL.createVault(msg.sender, duration, creatorFeeFactor, nftFeeFactor); 
    }

    /*//////////////////////////////////////////////////////////////
                                 STAKE
    //////////////////////////////////////////////////////////////*/

    ///@dev Calls stakeTokens
    function stakeTokens(bytes32 vaultId, uint256 amount) external {
        // call pool
        POOL.stakeTokens(vaultId, msg.sender, amount);
    }

    ///@dev Calls stakeNfts
    function stakeNfts(bytes32 vaultId, uint256[] calldata tokenIds) external {
        // call pool
        POOL.stakeNfts(vaultId, msg.sender, tokenIds);
    }


    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/

    ///@dev 
    function claimFees(bytes32 vaultId) external {
        POOL.claimFees(vaultId, msg.sender);
    } 

    function claimRewards(bytes32 vaultId) external {
        POOL.claimRewards(vaultId, msg.sender);
    } 


    /*//////////////////////////////////////////////////////////////
                                UNSTAKE
    //////////////////////////////////////////////////////////////*/

    function unstakeAll(bytes32 vaultId) external {
        POOL.unstakeAll(vaultId, msg.sender);
    }


    /*//////////////////////////////////////////////////////////////
                            FEES + LIMIT
    //////////////////////////////////////////////////////////////*/

    ///@notice Only allowed to increase nft fee factor
    function updateNftFee(bytes32 vaultId, uint256 amount, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        //note: 50 RP needed to adjust fees
        _checkAndBurnRp(50, realmId, v, r, s);

        POOL.updateNftFee(vaultId, msg.sender, amount);
    }

    ///@notice Only allowed to reduce the creator fee factor
    function updateCreatorFee(bytes32 vaultId, uint256 amount, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        //note: 50 RP needed to adjust fees
        _checkAndBurnRp(50, realmId, v, r, s);

        POOL.updateCreatorFee(vaultId, msg.sender, amount);
    }


    // increase limit by the amount param. 
    // RP required = 50 + X. X goes towards calc. staking increment. 50 is a base charge.
    function increaseVaultLimit(bytes32 vaultId, uint256 amount, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        require(amount > MOCA_INCREMENT_PER_RP, "Invalid increment");

        // calc. RP required. fee charge: 50 RP, every RP thereafter contributes to incrementing the limit
        // division involves rounding down
        uint256 rpRequired = (amount / MOCA_INCREMENT_PER_RP) + 50;
        _checkAndBurnRp(rpRequired, realmId, v, r, s);

        uint256 limitIncrement = (rpRequired * MOCA_INCREMENT_PER_RP);
        POOL.increaseVaultLimit(vaultId, msg.sender, limitIncrement);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

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



}