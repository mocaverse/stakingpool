// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title Errors library
 * @author Calnix
 * @notice Defines the error messages emitted by the different contracts of the Moca protocol
 */

library Errors {

    error Test(uint256 counter);
    
    error InvalidVaultPeriod();
    error InvalidStakingPeriod();
    error InsufficientTimeLeft();

    error NonExistentVault(bytes32 vaultId);
    error UserIsNotVaultCreator(bytes32 vaultId, address user) ;

    error VaultMatured(bytes32 vaultId);
    error VaultNotMatured(bytes32 vaultId);
    
    error UserHasNoNftStaked(bytes32 vaultId, address user);
    error UserHasNoTokenStaked(bytes32 vaultId, address user);
    error UserHasNothingStaked(bytes32 vaultId, address user);

    error TotalFeeFactorExceeded();
    error NftFeeCanOnlyBeIncreased(bytes32 vaultId);
    error CreatorFeeCanOnlyBeDecreased(bytes32 vaultId);
    
    error NftStakingLimitExceeded(bytes32 vaultId, uint256 currentNftAmount);
    error StakedTokenLimitExceeded(bytes32 vaultId, uint256 currentTokenAmount);

    error InvalidEmissionParameters();

    error InsufficientRealmPoints(uint256 currentRealmPoints, uint256 requiredRealmPoints);

    error VaultHasZeroStakedTokens();
    error VaultHasZeroStakedNfts();
}
