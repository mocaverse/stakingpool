// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPool {

    function stakeTokens(bytes32 vaultId, address onBehalfOf, uint256 amount) external;
    function stakeNfts(bytes32 vaultId, address onBehalfOf, uint256 amount) external;

    function unstakeAll(bytes32 vaultId, address onBehalfOf) external;
    
    function claimFees(bytes32 vaultId, address onBehalfOf) external;
    function claimRewards(bytes32 vaultId, address onBehalfOf) external;

    function updateCreatorFee(bytes32 vaultId, address onBehalfOf, uint256 amount) external;
    function increaseVaultLimit(bytes32 vaultId, address onBehalfOf, uint256 amount) external;
    function updateNftFee(bytes32 vaultId, address onBehalfOf, uint256 amount) external;

}