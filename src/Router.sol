// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from './Errors.sol';
import {IPool} from "./interfaces/IPool.sol";
import {IMocaPoints} from "./interfaces/IMocaPoints.sol";
import {RevertMsgExtractor} from "./utils/RevertMsgExtractor.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

//note: inherit forwarder stuff

contract Router {
    using SafeERC20 for IERC20;

    address public STAKED_TOKEN;  

    IPool public POOL;
    IMocaPoints public immutable REALM_POINTS;

// ------- [note: need to confirm values] -------------------

    //increments
    uint256 public constant MOCA_INCREMENT_PER_RP = 800 * 1e18;    
    
    // realm points 
    bytes32 public constant season = hex"01"; 
    bytes32 public constant consumeReasonCode = hex"01";

//-------------------------------Events---------------------------------------------

    // events
    event RealmPointsBurnt(uint256 realmId, uint256 rpBurnt);

//------------------------------- fns -------------------------------------------

    constructor(address mocaToken, address pool, address realmPoints){
        STAKED_TOKEN = mocaToken;
        POOL = IPool(pool);
        REALM_POINTS = IMocaPoints(realmPoints);
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


    function stake(
        bytes32 vaultId,
        address token,
        address owner,         // user
        address spender,       // router
        uint256 amount,        // amount of tokens
        uint256 deadline,      // expiry
        uint8 v, bytes32 r, bytes32 s) external {
            
        //1. permit: gain approval for stkMOCA frm user via sig
        IERC20Permit(token).permit(owner, spender, amount, deadline, v, r, s);

        //stake: router calls pool -> transferFrom 
        IPool(spender).stakeTokens(vaultId, owner, amount);

    }

    // increase limit by the amount param. 
    // RP required = 50 + X. X goes towards calc. staking increment. 50 is a base charge.
    function increaseVaultLimit(bytes32 vaultId, address onBehalfOf, uint256 amount, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        require(amount > MOCA_INCREMENT_PER_RP, "Invalid increment");

        // calc. RP required. fee charge: 50 RP, every RP thereafter contributes to incrementing the limit
        // division involves rounding down
        uint256 rpRequired = (amount / MOCA_INCREMENT_PER_RP) + 50;
        _checkAndBurnRp(rpRequired, realmId, v, r, s);

        uint256 limitIncrement = (rpRequired * MOCA_INCREMENT_PER_RP);
        POOL.increaseVaultLimit(vaultId, onBehalfOf, limitIncrement);

    }

    ///@notice Only allowed to reduce the creator fee factor
    function updateCreatorFee(bytes32 vaultId, address onBehalfOf, uint256 newCreatorFeeFactor, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        
        //note: 50 RP needed to adjust fees
        _checkAndBurnRp(50, realmId, v, r, s);

        POOL.updateCreatorFee(vaultId, onBehalfOf, newCreatorFeeFactor);
    }

    function updateNftFee(bytes32 vaultId, address onBehalfOf, uint256 newCreatorFeeFactor, uint256 realmId, uint8 v, bytes32 r, bytes32 s) external {
        
        //note: 50 RP needed to adjust fees
        _checkAndBurnRp(50, realmId, v, r, s);

        POOL.updateNftFee(vaultId, onBehalfOf, newCreatorFeeFactor);
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
}


/**
Batch teh following
1. create permit: message for user to sign - gives approval
2. batch: permit sig verification, stake
3. 
 */