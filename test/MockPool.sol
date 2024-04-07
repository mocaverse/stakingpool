// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "./../src/Pool.sol";

contract MockPool is Pool {

    constructor(
        IERC20 stakedToken, IERC20 rewardToken, address realmPoints, address rewardsVault, address registry, 
        uint256 startTime_, uint256 duration, uint256 rewards,
        string memory name, string memory symbol, address owner) payable 
        
        Pool(stakedToken, rewardToken, realmPoints, rewardsVault, registry, 
        startTime_, duration, rewards,
        name, symbol, owner)
        {}

    
    function getUserInfoStruct(bytes32 vaultId, address user) public view returns (DataTypes.UserInfo memory) {

        DataTypes.UserInfo memory userInfo = users[user][vaultId];
        return userInfo;
    }

    function getVaultStruct(bytes32 vaultId) public view returns (DataTypes.Vault memory) {

        DataTypes.Vault memory vault = vaults[vaultId];
        return vault;
    }

    function getPoolStruct() public view returns (DataTypes.PoolAccounting memory) {
        DataTypes.PoolAccounting memory pool = pool;
        return pool;
    }

}