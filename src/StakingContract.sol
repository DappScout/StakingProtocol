// SPDX-License-identifier: MIT
pragma solidity 0.8.28;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Simple Staking Protocol
 * @author DappScout
 * @notice Contract for managing staking logic, rewards management and emergency pausing
 * @dev Contract should be ownable, pausable,
 */
contract StakingContract is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////
                    VARIABLES
    //////////////////////////////////////////////////////*/

    ///@notice The token that users can stake in this contract
    IERC20 public immutable i_stakingToken;

    uint256 public immutable i_minimalStakeAmount;

    ///@notice A stake variable to track whole amount staked
    uint256 public s_totalStakedAmount;

    uint256 public MINIMAL_TIME_BETWEEN = 1 hours;

    ///@notice Parameter that defines a reward rate per second
    uint256 internal s_rewardRate = 10;
    uint256 internal constant BASIS_POINTS = 10000;


    /*//////////////////////////////////////////////////////
                    STRUCTS
    //////////////////////////////////////////////////////*/

    struct UserData{
        uint256 stakedAmount;
        uint256 rewards;
        uint256 lastTimeStamp;
        uint256 rewardDebt;
    }

    /*//////////////////////////////////////////////////////
                    MAPPINGS
    //////////////////////////////////////////////////////*/

    mapping(address => UserData) public userData;


    /*//////////////////////////////////////////////////////
                    EVENTS
    //////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event Paused();
    event Unpaused();

    /*//////////////////////////////////////////////////////
                    ERRORS
    //////////////////////////////////////////////////////*/

    error StakingContract_WrongAmountGiven();
    error StakingContract_InsufficientBalance();
    error StakingContract_ToEarly();
    error StakingContract_SomethingWentWrong();

    /*//////////////////////////////////////////////////////
                    CONSTRUCTOR
    //////////////////////////////////////////////////////*/

    constructor(address initialOwner, address _stakingTokenAddress, uint256 _i_minimalStakeAmount)
        Ownable(initialOwner)
    {
        i_minimalStakeAmount = _i_minimalStakeAmount;
        i_stakingToken = IERC20(_stakingTokenAddress);
    }

    /*//////////////////////////////////////////////////////
                    MODIFIERS
    //////////////////////////////////////////////////////*/

    modifier updateReward(address _user) {

        if(_user == address(0)){revert StakingContract_SomethingWentWrong();}

        UserData storage userTime = userData[_user].lastTimeStamp;
        
        ///@notice Check if rewards calculations are needed
        if(userTime != 0){

        ///@notice Check that reverts a call to prevent too frequent calls.
        if(block.timestamp < userData[_user].lastTimeStamp + MINIMAL_TIME_BETWEEN) {
            revert StakingContract_ToEarly();
            }
            
            calculateRewards(_user);
        }
        _;
    }
        
    

    /*//////////////////////////////////////////////////////
                    MAIN FUNCTIONS
    //////////////////////////////////////////////////////*/

    /**
     * @notice Allows users to stake a specified amount of tokens.
     *         Staking is allowed only when protocol is not paused by the owner
     * @dev  Can be done by regular user, but not the owner
     *
     */

    /*
        Checks:
            minimal amount
            not zero
            rate limit(slash loans)
            
        add amount to user ballance - done
        update the token rewards
        early unstake penalty mechanism
    */

    function stake(uint256 _amount) public whenNotPaused nonReentrant updateReward(msg.sender){
        //check if some dust amounts can disturb the protocol
        if (_amount < i_minimalStakeAmount) revert StakingContract_WrongAmountGiven();

        if (i_stakingToken.balanceOf(msg.sender) < _amount) revert StakingContract_InsufficientBalance();

        userData[msg.sender].stakedAmount = userData[msg.sender].stakedAmount + _amount;

        s_totalStakedAmount = s_totalStakedAmount + _amount;

        i_stakingToken.safeTransferFrom(msg.sender, address(this), _amount);


        if(user.lastTimeStamp == 0){
            user.lastTimeStamp = block.timestamp;
            return;
        }

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Allows users to withdraw a portion of their staked tokens.
     *         Staking is allowed only when protocol is not paused by the owner
     */
    function unstake(uint256 _amount) public whenNotPaused nonReentrant updateReward(msg.sender){
        
        if(_amount > userData[msg.sender].stakedAmount) revert StakingContract_WrongAmountGiven(); // check if staked amount is greater than unstake amount
        
        userData[msg.sender].stakedAmount = userData[msg.sender].stakedAmount - _amount;
        i_stakingToken.safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @notice Enables users to claim their accumulated rewards
     *         Staking is allowed only when protocol is not paused by the owner
     */
    function claimRewards() public whenNotPaused nonReentrant updateReward(msg.sender){


    }



    /**
     * @notice Permits the owner to halt and resume staking operations.
     *         Staking is allowed only when protocol is not paused by the owner
     */
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() public onlyOwner whenPaused {
        _unpause();
    }


    function calculateRewards(address _user) internal {
    // check precision loss mitigation  
    // check first stake calulations - potencial precision loss

        UserData storage user = userData[_user];


        if (user.stakedAmount == 0) {
            return;
        }


        uint256 passedTime = block.timestamp - user.lastTimeStamp;

        uint256 newRewards = (user.stakedAmount * s_rewardRate * passedTime) / BASIS_POINTS;

        user.rewards = user.rewards + newRewards;

        user.lastTimeStamp = block.timestamp;


        ///@notice update total staked amount
        s_totalStakedAmount = s_totalStakedAmount - user.stakedAmount;

        ///Unde construction - Something is not working here - Check
    }

    ///@notice Function for admin to change reward rate
    function setRewardRate(uint256 _s_rewardRate) external onlyOwner{
        s_rewardRate = _s_rewardRate;
    }

    /*//////////////////////////////////////////////////////
                    GETTER FUNCTIONS
    //////////////////////////////////////////////////////*/

    function getStakedBalance(address _staker) public view returns (uint256) {
        return userData[_staker].stakedAmount;
    }



    function getRewardDebt(address _staker) public view returns (uint256) {
        return userData[_staker].rewardDebt;
    }
}
