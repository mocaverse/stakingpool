// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @title Simple reward vault contract for supporting pool
/// @author Calnix
/// @dev Admin can recover other random tokens sent to the vault accidentally.
/// @dev Only Money Manager can fund and withdraw the defined reward token.
/// @notice This is a simple cut-down version for illustration, not meant for production.

contract RewardsVault is AccessControl {
    using SafeERC20 for IERC20;

    uint256 public totalVaultRewards;
    IERC20 public immutable REWARD_TOKEN;
    
    // roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MONEY_MANAGER_ROLE = keccak256("MONEY_MANAGER_ROLE");

    // events
    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Recovered(address indexed token, address indexed target, uint256 amount);
    
    constructor(IERC20 rewardToken, address moneyManager, address admin) {

        REWARD_TOKEN = rewardToken;
        _grantRole(MONEY_MANAGER_ROLE, moneyManager);
        _grantRole(ADMIN_ROLE, admin);

    }

    /**
     * @notice Deposit rewards into the vault
     * @param from Address from which rewards are to be pulled
     * @param amount Rewards amount (in wei)
     */
    function deposit(address from, uint256 amount) onlyRole(MONEY_MANAGER_ROLE) external {
                
        REWARD_TOKEN.safeTransferFrom(from, address(this), amount);
        emit Deposit(from, amount);
    }

    /**
     * @notice Withdraw rewards from the vault
     * @param to Address from which rewards are to be pulled
     * @param amount Rewards amount (in wei)
     */
    function withdraw(address to, uint256 amount) onlyRole(MONEY_MANAGER_ROLE) external {
        REWARD_TOKEN.safeTransfer(to, amount);
        emit Withdraw(to, amount);
    }

        
    /*//////////////////////////////////////////////////////////////
                                RECOVER
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Recover random tokens accidentally sent to the vault
     * @param tokenAddress Address of token contract
     * @param amount Amount to retrieve
     */
    function recoverERC20(address tokenAddress, address target, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(tokenAddress != address(REWARD_TOKEN), "Out-of-scope");
        
        IERC20(tokenAddress).safeTransfer(target, amount);
        emit Recovered(tokenAddress, target, amount);
    }


}
