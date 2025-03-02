// SPDX-License-identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ScoutToken} from "./TokenERC20.sol";

// @title Simple Staking Protocol
// @author DappScout
// @notice Contract for managing staking logic, rewards management and emergency pausing
contract StakingContract is Ownable(msg.sender), Pausable {
    uint256 test;

    mapping(address => uint256) private stakes;

    constructor(address _initialOwner) {}

// @notice Allows users to stake a specified amount of tokens.
function stake(uint256 amount){

}
// @notice Allows users to withdraw a portion of their staked tokens.
function unstake(uint256 amount){

}
// @notice Enables users to claim their accumulated rewards
function claimRewards(){

}

// @notice Permits the owner to halt and resume staking operations.
function pause{

}


// Getter functions
 function getStakedBalance() pubic pure returns (uint256){

 }

}

/*
add staking functions
add unstaking function
reward accumulation - function/modifier?
pausing functionality for emengency - modifier and function for pausing? Some


check how to safely do:
state management, 
reward calculation, 
access control, 
pausing mechanisms
secure token transfers
*/