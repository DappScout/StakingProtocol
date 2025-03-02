// SPDX-License-identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ScoutToken} from "./TokenERC20.sol";

//check if its good to implement
using SafeERC20 for IERC20; //https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20

/* @title Simple Staking Protocol
 * @author DappScout
 * @notice Contract for managing staking logic, rewards management and emergency pausing
 * @dev Contract should be ownable, pausable,
 */
contract StakingContract is Ownable(msg.sender), Pausable {
    mapping(address => uint256) private stakes;
    mapping(address => uint256) private rewardDebt;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event Paused();
    event Unpaused();

    constructor(address _initialOwner) {}

    // @notice Allows users to stake a specified amount of tokens.
    function stake(uint256 amount) public {}
    // @notice Allows users to withdraw a portion of their staked tokens.
    function unstake(uint256 amount) public {}
    // @notice Enables users to claim their accumulated rewards
    function claimRewards() public {}

    // @notice Permits the owner to halt and resume staking operations.
    function pause() public {}

    /* Concept:
    - should this be executed at the begining of every transaction?
    - This

    */
    function calculateRewards() private {}

    // Getter functions
    function getStakedBalance(address _staker) public view returns (uint256) {
        return stakes[_staker];
    }

    function getRewardDebt(address _staker) public view returns (uint256) {
        return rewardDebt[_staker];
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
