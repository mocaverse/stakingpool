// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMocaPoints {

    function consume(bytes32 parentNode, string calldata name, uint256 amount, bytes32 consumeReasonCode, uint8 v, bytes32 r, bytes32 s) external;
    function consume(uint256 realmId, uint256 amount, bytes32 consumeReasonCode, uint8 v, bytes32 r, bytes32 s) external;
    function consume(bytes32 parentNode, string calldata name, uint256 amount, bytes32 consumeReasonCode) external;
    function consume(uint256 realmId, uint256 amount, bytes32 consumeReasonCode) external;

    function balanceOf(bytes32 season, uint256 realmId) external returns (uint256);
    function balanceOf(bytes32 season, bytes32 parentNode, string calldata name) external returns (uint256);
    function balanceOf(uint256 realmId) external returns (uint256);
    function balanceOf(bytes32 parentNode, string calldata name) external returns (uint256); 

}