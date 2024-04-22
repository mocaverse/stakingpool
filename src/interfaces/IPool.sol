// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DataTypes} from 'src/DataTypes.sol';

interface IPool {

    function createVault(address onBehalfOf, DataTypes.VaultDuration duration, uint256 creatorFeeFactor, uint256 nftFeeFactor) external;

    function stakeTokens(bytes32 vaultId, address onBehalfOf, uint256 amount) external;
    function stakeNfts(bytes32 vaultId, address onBehalfOf,  uint256[] calldata tokenIds) external;

    function claimFees(bytes32 vaultId, address onBehalfOf) external;
    function claimRewards(bytes32 vaultId, address onBehalfOf) external;

    function unstakeAll(bytes32 vaultId, address onBehalfOf) external;
    
    function updateNftFee(bytes32 vaultId, address onBehalfOf, uint256 newNftFeeFactor) external;
    function updateCreatorFee(bytes32 vaultId, address onBehalfOf, uint256 newCreatorFeeFactor) external;
    function increaseVaultLimit(bytes32 vaultId, address onBehalfOf, uint256 amount) external;

}