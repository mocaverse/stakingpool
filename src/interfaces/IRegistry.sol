// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IRegistry {

    function recordStake(address onBehalfOf, uint256[] calldata tokenIds, bytes32 vaultId) external;
    function recordUnstake(address onBehalfOf, uint256[] calldata tokenIds, bytes32 vaultId) external;
    
}