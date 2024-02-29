// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPool} from "./interfaces/IPool.sol";
import {RevertMsgExtractor} from "./utils/RevertMsgExtractor.sol";
import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract Router {
    using SafeERC20 for IERC20;

    address public STAKED_TOKEN;  
    address public LOCKED_NFT_TOKEN;  

    constructor(address mocaToken, address mocaNFT){
        STAKED_TOKEN = mocaToken;
        LOCKED_NFT_TOKEN = mocaNFT;
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

}


/**
Batch teh following
1. create permit: message for user to sign - gives approval
2. batch: permit sig verification, stake
3. 
 */


 /**
 Gas-less Token Transfer - Code: https://www.youtube.com/watch?v=jYNnatXRsBs
  */

// sig is created on the FE. 
// wb NFT chips?


/**
1) NFT registry does not issue erc20 token.
    no. of nfts per user recorded in mapping
    when user wishes to stake nft, router calls registry to check if there are available nfts
    Once an nft is staked, registry must be updated by the stakingPool, to "lock" nfts
     increment lockAmount
     decrement availableAmount

Since no tokens are used in this approach, users will not be able to "see" anything
in their metamask wallet

2) NFT registry issues erc20 token.
    On locking the nFT on mainnet, registry issues bridgedNftToken to user, on polygon
    user can stake bridgedNFTToken into stakingPool
    on staking, user transfers bridgedNftToken to pool, and receives stkNftToken.

    This means tt while registry can inherit bridgedNFTToken.
    We will need a standalone erc20 token contract for stkNftToken.
    stakinPool cannot inherit this, since it already inherits stkMocaToken.

    registry mints user bridgedNFTToken
    bridgedNFTToken transferred to stakingPool
    - bridgedNFTToken must be freely mint/burn and transferable

    stakinPool mints/burns stkNftToken
    - stkNftToken can be non-transferable.

bridgedNFTToken will need to be ERC20Permit, for gassless transfer on staking.

 */


/**


 */