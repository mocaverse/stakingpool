// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2, stdStorage, StdStorage} from "forge-std/Test.sol";

import "./../src/testpermit.sol";

abstract contract StateZero is Test {
    TestToken public testToken;

        address public userA = address(0xA);
        address public  userB = address(0xB);
        address public  userC = address(0xC);

    function setUp() public virtual {
        
        vm.prank(userA);
        testToken = new TestToken("MocaToken", "MOCA");
    }

}

contract TokenTest is StateZero {

    function testCap() public{
        testToken.mint(address(1), 200 ether);
    }

    function testUpdate() public{
        vm.prank(userA);
        testToken.mint(userB, 100 ether);

        vm.prank(userB);
        testToken.transfer(userC, 12 ether);
    }
}