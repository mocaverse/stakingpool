// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Capped} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract TestToken is ERC20Permit, ERC20Capped {

    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) ERC20Capped(200e18){}

    function mint(address user, uint256 amount) external {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) external {
        _burn(user, amount);
    }

    
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }
}