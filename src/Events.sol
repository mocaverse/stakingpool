// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {DataTypes} from './DataTypes.sol';

event DistributionUpdated(uint256 indexed newPoolEPS, uint256 indexed newEndTime);
event RouterUpdated(address indexed oldRouter, address indexed newRouter);

event PoolIndexUpdated(uint256 indexed lastUpdateTimestamp, uint256 indexed oldIndex, uint256 indexed newIndex);
event VaultIndexUpdated(bytes32 indexed vaultId, uint256 indexed vaultIndex, uint256 indexed vaultAccruedRewards);
event VaultMultiplierUpdated(bytes32 indexed vaultId, uint256 indexed oldMultiplier, uint256 indexed newMultiplier);

event UserIndexesUpdated(address indexed user, bytes32 indexed vaultId, uint256 userIndex, uint256 userNftIndex, uint256 userAccruedRewards);

event VaultCreated(address indexed creator, bytes32 indexed vaultId, uint256 indexed endTime, DataTypes.VaultDuration duration);

event StakedMoca(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
event StakedMocaNft(address indexed onBehalfOf, bytes32 indexed vaultId, uint256[] indexed tokenIds);
event UnstakedMoca(address indexed onBehalfOf, bytes32 indexed vaultId, uint256 amount);
event UnstakedMocaNft(address indexed onBehalfOf, bytes32 indexed vaultId, uint256[] indexed tokenIds);

event RewardsAccrued(address indexed user, uint256 amount);
event NftRewardsAccrued(address indexed user, uint256 amount);

event RewardsClaimed(bytes32 indexed vaultId, address indexed user, uint256 amount);
event NftRewardsClaimed(bytes32 indexed vaultId, address indexed creator, uint256 amount);
event CreatorRewardsClaimed(bytes32 indexed vaultId, address indexed creator, uint256 amount);

event CreatorFeeFactorUpdated(bytes32 indexed vaultId, uint256 indexed oldCreatorFeeFactor, uint256 indexed newCreatorFeeFactor);
event NftFeeFactorUpdated(bytes32 indexed vaultId, uint256 indexed oldCreatorFeeFactor, uint256 indexed newCreatorFeeFactor);

event RecoveredTokens(address indexed token, address indexed target, uint256 indexed amount);
event PoolFrozen(uint256 indexed timestamp);

event VaultStakingLimitIncreased(bytes32 indexed vaultId, uint256 oldStakingLimit, uint256 indexed newStakingLimit);