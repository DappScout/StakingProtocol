// SPDX-License-identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//check if its good to implement
using SafeERC20 for IERC20; //https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20

/** @title Simple Staking Protocol
 * @author DappScout
 * @notice Contract for managing staking logic, rewards management and emergency pausing
 * @dev Contract should be ownable, pausable,
 */
contract StakingContract is Ownable, Pausable, ReentrancyGuard {

///////////////////////////////////////////////////  
/////////////////////VARIABLES/////////////////////
/////////////////////////////////////////////////// 

    /** 
    * @notice A stake variable to track whole amount staked
    */ 
    IERC20 public immutable i_stakingToken;

    /** 
    * @notice A stake variable to track whole amount staked
    */ 
    uint256 internal totalStakedAmount;

    /** 
    * @notice Parameter that defines a reward rate per second
    */ 
    uint256 internal rewardRate;
    
    uint256 internal lastBlockNumber;
    
////////////////////////Mappings/////////////////////////// 
    /** 
    * @notice 
    */
    mapping(address user => uint256 stakedAmount) private stakes;
    
    mapping(address user => uint256 paidRewards) private paidRewards;

    /** 
    * @notice 
    */
    mapping(address => uint256) private rewardDebt;

/////////////////////////////////////////////////// 
/////////////////////EVENTS////////////////////////
/////////////////////////////////////////////////// 

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event Paused();
    event Unpaused();
/////////////////////////////////////////////////// 
/////////////////////ERRORS////////////////////////
///////////////////////////////////////////////////

error StakingContract_WrongAmountGiven();



/////////////////////////////////////////////////////
/////////////////////CONSTRUCTOR/////////////////////
/////////////////////////////////////////////////////

constructor(address _initialOwner) {

}

/*////////////////////////////////////////////////// 
/////////////////////MODIFIERS/////////////////////
//////////////////////////////////////////////////*/ 

receive() external payable{



}

/*///////////////////////////////////////////////////////
                    MAIN FUNCTIONS
///////////////////////////////////////////////////////*/
  
    /** 
    * @notice Allows users to stake a specified amount of tokens.
    *         Staking is allowed only when protocol is not paused by the owner
    * @dev  Can be done by regular user, but not the owner
    *       
    */ 
    function stake(uint256 _amount) public whenNotPaused nonReentrant{
        // if(_amount < minimalStakeAmount) revert StakingContract_WrongAmountGiven();

        calculateRewards(msg.sender);
        stakes[msg.sender] = stakes[msg.sender] + _amount;
    }

    /** 
    * @notice Allows users to withdraw a portion of their staked tokens.
    *         Staking is allowed only when protocol is not paused by the owner
    */ 

    function unstake(uint256 _amount) public whenNotPaused nonReentrant{
        // if(_amount <= balanceOf[msg.sender]) revert StakingContract_WrongAmountGiven(); // check if balance is greater than unstake amount 
        // if() revert; //is not zero, or dust amount


    }
    
    
    
    
    /** 
    * @notice Enables users to claim their accumulated rewards
    *         Staking is allowed only when protocol is not paused by the owner
    */ 

    function claimRewards() public whenNotPaused nonReentrant{}

    /** 
    * @notice Permits the owner to halt and resume staking operations.
    *         Staking is allowed only when protocol is not paused by the owner
    */ 

    function pause() public onlyOwner whenNotPaused{

    }

    function unpause() public onlyOwner whenPaused(){

    }


    /* Concept:
    - should this be executed at the begining of every transaction?
    - This

    */
    function calculateRewards(address _user) private {

    uint256 rewardPerToken = (rewardRate / totalStakedAmount) * (block.number - lastBlockNumber);

    rewards[_user] = stakes[_user] * (rewardPerToken * paidRewards[_user]); 
    ///@notice update already paid token rewards to user
    paidRewards[_user] = rewardPerToken;
    
    ///@notice update last block number
    lastBlockNumber = block.number;

///Something is fucked here
    }




//////////////////////////////////////////////////////////
/////////////////////GETTER FUNCTIONS/////////////////////
//////////////////////////////////////////////////////////
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

Additional features:
Dynamic Reward Rate: Allow the owner to adjust the reward rate
Early Unstake Penalty: Implement a penalty for unstaking before a specified lock-up period.
*/
