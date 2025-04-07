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
    uint256 public s_totalRewardsAmount;

    uint256 public constant MINIMAL_CONTRACT_BALANCE_PERCENTAGE = 1000;
    uint256 public constant MINIMAL_TIME_BETWEEN = 1 hours;
    uint256 internal constant BASIS_POINTS = 10000;
    ///@notice Parameter that defines a reward rate per second
    uint256 internal s_rewardRate = 10;

    /*//////////////////////////////////////////////////////
                    STRUCTS
    //////////////////////////////////////////////////////*/

    struct UserData {
        uint256 stakedAmount;
        uint256 rewards;
        uint256 lastTimeStamp;
        uint256 rewardDebt;
    }


    /*//////////////////////////////////////////////////////
                    ARRAY
    //////////////////////////////////////////////////////*/

    address[] public stakers;

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
    event RewardsCalculated(address indexed user, uint256 reward);
    event RewardRateChanged(uint256 oldRate, uint256 newRate);
    event RewardReservesAreLow(uint256 minimalReserveAmount, uint256 minimalTotalReserves);

    /*//////////////////////////////////////////////////////
                    ERRORS
    //////////////////////////////////////////////////////*/

    error StakingContract_WrongAmountGiven();
    error StakingContract_InsufficientBalance();
    error StakingContract_ToEarly();
    error StakingContract_ClaimFailed();
    error StakingContract_SomethingWentWrong();
    error StakingContract_ContractInsufficientBalance();

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

    function stake(uint256 _amount) public whenNotPaused nonReentrant {


        //check if some dust amounts can disturb the protocol
        if (_amount < i_minimalStakeAmount) revert StakingContract_WrongAmountGiven();

        address staker = msg.sender;

        if (staker == address(0)) revert StakingContract_SomethingWentWrong();

        if (i_stakingToken.balanceOf(staker) < _amount) revert StakingContract_InsufficientBalance();

        UserData storage user = userData[staker];

        ///@notice Check that reverts a call to prevent too frequent calls.
        if (user.lastTimeStamp != 0 && block.timestamp < user.lastTimeStamp + MINIMAL_TIME_BETWEEN) {
            revert StakingContract_ToEarly();
        }

        ///@notice check for reserved token balance for rewards
        _checkReserves(_amount);


        ///@notice Check if rewards calculations are needed

        if (user.lastTimeStamp != 0) {
            _calculateRewards(staker);
            }
        else{
            stakers.push(staker);
            user.lastTimeStamp = block.timestamp;
        }

        user.stakedAmount = user.stakedAmount + _amount;

        s_totalStakedAmount = s_totalStakedAmount + _amount;

        i_stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Allows users to withdraw a portion of their staked tokens.
     *         Staking is allowed only when protocol is not paused by the owner
     */
    function unstake(uint256 _amount) public whenNotPaused nonReentrant {
        if (_amount > userData[msg.sender].stakedAmount) revert StakingContract_WrongAmountGiven(); // check if staked amount is greater than unstake amount

        _calculateRewards(msg.sender);

        userData[msg.sender].stakedAmount = userData[msg.sender].stakedAmount - _amount;

        ///@notice update total staked amount
        s_totalStakedAmount = s_totalStakedAmount - _amount;

        i_stakingToken.safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @notice Enables users to claim their accumulated rewards
     *         Staking is allowed only when protocol is not paused by the owner
     */
    function claimRewards() public whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256 protocolBalance = i_stakingToken.balanceOf(address(this));

        if (userData[sender].lastTimeStamp == 0) revert StakingContract_ClaimFailed();

        _calculateRewards(sender);

        uint256 rewardsToSend = userData[sender].rewards;

        if (protocolBalance < rewardsToSend) revert StakingContract_ClaimFailed();
        if (rewardsToSend == 0) revert StakingContract_ClaimFailed();

        userData[sender].rewards = 0;

        if (protocolBalance >= rewardsToSend) {
            i_stakingToken.safeTransfer(sender, rewardsToSend);
        } else {
            revert StakingContract_ClaimFailed();
        }

        emit RewardsClaimed(sender, rewardsToSend);
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

    ///@notice Function for admin to change reward rate
    function setRewardRate(uint256 _s_rewardRate) external onlyOwner {
        uint256 oldRate = _s_rewardRate;
        //calculate with the old rate
        _calculateAllRewards();

        //update to new rate
        s_rewardRate = _s_rewardRate;

        emit RewardRateChanged(oldRate, s_rewardRate);
    }

    /*//////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////*/


    /**
     * @notice Calculates and updates rewards for a user based on staking time and amount
     * @dev Uses a rate of s_rewardRate basis points per time unit
     * @param _user Address of the user to calculate rewards for
     */
    function _calculateRewards(address _user) internal {
        // check first stake calulations - potencial precision loss

        UserData storage user = userData[_user];

        ///@dev skip if user's stake is zero
        if (user.stakedAmount == 0) {
            return;
        }

        uint256 passedTime = block.timestamp - user.lastTimeStamp;

        uint256 newRewards = (user.stakedAmount * s_rewardRate * passedTime) / BASIS_POINTS;

        user.rewards = user.rewards + newRewards;
        s_totalRewardsAmount = s_totalRewardsAmount + newRewards;
        
        ///@note check potencial overflows

        user.lastTimeStamp = block.timestamp;

        emit RewardsCalculated(_user, user.rewards);
    }

    function _calculateAllRewards() internal {
        for (uint256 i = 0; i < stakers.length; i++) {
            address stakersAddress = stakers[i];

            if (userData[stakersAddress].stakedAmount > 0) {
                _calculateRewards(stakersAddress);
            }
        }
    }

    function _checkReserves(uint256 _stakedAmount) internal{

        uint256 minimalReserveAmount = (s_totalStakedAmount * MINIMAL_CONTRACT_BALANCE_PERCENTAGE)/ BASIS_POINTS; 

        uint256 requiredAmountTotal = s_totalStakedAmount + s_totalRewardsAmount + minimalReserveAmount;

        uint256 currentBalance = i_stakingToken.balanceOf(address(this));
        
        if(currentBalance < requiredAmountTotal){
            emit RewardReservesAreLow(minimalReserveAmount ,requiredAmountTotal);
            revert StakingContract_ContractInsufficientBalance();
        }
    }

    /*//////////////////////////////////////////////////////
                    GETTER FUNCTIONS
    //////////////////////////////////////////////////////*/

    function getStakedBalanceOf(address _staker) public view returns (uint256) {
        return userData[_staker].stakedAmount;
    }

    function getRewardDebt(address _staker) public view returns (uint256) {
        return userData[_staker].rewardDebt;
    }

    function getStakersLength() public view returns (uint256){
        return stakers.length;
    }

}
