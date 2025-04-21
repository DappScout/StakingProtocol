// SPDX-License-Identifier: MIT

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
 * @dev Implements a staking system with reward distribution based on time staked
 *      Uses OpenZeppelin's Ownable for access control, Pausable for emergency stops,
 *      and ReentrancyGuard for protection against reentrancy attacks
 */
contract StakingContract is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////
                    VARIABLES
    //////////////////////////////////////////////////////*/

    /// @notice The token that users can stake in this contract
    IERC20 public immutable i_stakingToken;

    /// @notice Minimum amount that can be staked
    /// @dev Prevents dust attacks
    uint256 public immutable i_minimalAmount;

    /// @notice Total amount of tokens staked across all users
    /// @dev Used for calculating rewards and contract's checks
    uint256 public s_totalStakedAmount;

    /// @notice Total amount of pending rewards of all users
    /// @dev Used for tracking overall reward distribution
    uint256 public s_totalRewardsAmount;

    /// @notice Minimal reserve of tokens for rewards as percentage of total staked amount
    /// @dev Represented in basis points (1e17 = 10%)
    uint256 public constant MINIMAL_CONTRACT_BALANCE_PERCENTAGE = 1e17;

    /// @notice Minimum time between certain actions
    /// @dev Used to prevent attacks related to quick transactions
    uint256 public constant MINIMAL_TIME_BETWEEN = 1 hours;

    /// @notice Basis points for percentage calculations
    /// @dev 1e18 = 100%, so divide by this for percentage calculations
    uint256 public constant BASIS_POINTS = 1e18;

    /// @notice Parameter that defines a reward rate per second
    /// @dev Current value (1_000_000_000) results in approximately 3% APY
    /// @dev Can be adjusted by the contract owner
    uint256 public s_rewardRate = 1_000_000_000;

    /*//////////////////////////////////////////////////////
                    STRUCTS
    //////////////////////////////////////////////////////*/

    /// @notice Data structure for tracking user staking information
    /// @dev Stored in a mapping for each user address
    /// @param stakedAmount Amount of tokens the user has staked
    /// @param rewards Accumulated rewards not yet claimed by the user
    /// @param lastTimeStamp Last time rewards were calculated for this user
    struct UserData {
        uint256 stakedAmount;
        uint256 rewards;
        uint256 lastTimeStamp;
    }

    /*//////////////////////////////////////////////////////
                    ARRAY
    //////////////////////////////////////////////////////*/

    /// @notice Array of all addresses that have staked tokens
    /// @dev Used for iterating through all stakers when recalculating rewards
    address[] public stakers;

    /*//////////////////////////////////////////////////////
                    MAPPINGS
    //////////////////////////////////////////////////////*/

    /// @notice Maps staker addresses to their staking data
    /// @dev Key is user address, value is UserData struct
    mapping(address => UserData) public userData;

    /*//////////////////////////////////////////////////////
                    EVENTS
    //////////////////////////////////////////////////////*/

    /// @notice Emitted when a user stakes tokens
    /// @param user Address of the user who staked tokens
    /// @param amount Amount of tokens staked
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user unstakes tokens
    /// @param user Address of the user who unstaked tokens
    /// @param amount Amount of tokens unstaked
    event Unstaked(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims their rewards
    /// @param user Address of the user who claimed rewards
    /// @param reward Amount of rewards claimed
    event RewardsClaimed(address indexed user, uint256 reward);

    /// @notice Emitted when rewards are calculated for a user
    /// @param user Address of the user whose rewards were calculated
    /// @param reward Updated reward amount after calculation
    event RewardsCalculated(address indexed user, uint256 reward);

    /// @notice Emitted when the reward rate is changed
    /// @param oldRate Previous reward rate
    /// @param newRate New reward rate
    event RewardRateChanged(uint256 oldRate, uint256 newRate);

    /*//////////////////////////////////////////////////////
                    ERRORS
    //////////////////////////////////////////////////////*/

    /// @notice Thrown when user has insufficient token balance for an operation
    error StakingContract_InsufficientBalance();

    /// @notice Thrown when attempting an action too soon after a previous action
    error StakingContract_TooEarly();

    /// @notice Thrown when claiming rewards fails due to contract issues
    error StakingContract_ClaimFailed();

    /// @notice Generic error for unexpected conditions
    error StakingContract_SomethingWentWrong();

    /// @notice Thrown when contract doesn't have sufficient balance for operations
    error StakingContract_ContractInsufficientBalance();

    /// @notice Thrown when attempting to claim rewards but none are available
    error StakingContract_NoRewardsAvailable();

    /// @notice Thrown when an input value is outside acceptable parameters
    error StakingContract_IncorrectInputValue();

    /*//////////////////////////////////////////////////////
                    CONSTRUCTOR
    //////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the staking contract
     * @dev Sets immutable variables and ownership
     * @param initialOwner Address that will have owner privileges
     * @param _stakingTokenAddress Address of the ERC20 token to be staked
     * @param _i_minimalAmount Minimum amount of tokens that can be staked
     */
    constructor(address initialOwner, address _stakingTokenAddress, uint256 _i_minimalAmount) Ownable(initialOwner) {
        i_minimalAmount = _i_minimalAmount;
        i_stakingToken = IERC20(_stakingTokenAddress);
    }

    /*//////////////////////////////////////////////////////
                    MODIFIERS
    //////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////
                    MAIN FUNCTIONS
    //////////////////////////////////////////////////////*/

    /**
     * @notice Allows users to stake a specified amount of tokens
     * @dev Calculates rewards for previous stakes, updates user data,
     *      and transfers tokens from user to contract
     * @dev Guards against reentrancy and enforces minimum stake amount
     * @dev Can only be called when contract is not paused
     * @dev Rate limited to prevent too frequent transactions (MINIMAL_TIME_BETWEEN)
     * @param _amount Amount of tokens to stake
     */
    function stake(uint256 _amount) public whenNotPaused nonReentrant {
        if (_amount == 0 || _amount < i_minimalAmount) revert StakingContract_IncorrectInputValue();

        address staker = msg.sender;

        UserData storage user = userData[staker];

        if (user.lastTimeStamp != 0 && block.timestamp < user.lastTimeStamp + MINIMAL_TIME_BETWEEN) {
            revert StakingContract_TooEarly();
        }

        if (user.lastTimeStamp != 0) {
            _calculateRewards(staker);
        } else {
            stakers.push(staker);
            user.lastTimeStamp = block.timestamp;
        }

        user.stakedAmount = user.stakedAmount + _amount;

        s_totalStakedAmount = s_totalStakedAmount + _amount;

        _checkReserves(_amount);

        i_stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Allows users to withdraw a portion of their staked tokens
     * @dev Calculates rewards before unstaking, updates user data,
     *      and transfers tokens from contract to user
     * @dev Guards against reentrancy and validates unstake amount
     * @dev Can only be called when contract is not paused
     * @dev Rate limited to prevent too frequent transactions
     * @param _amount Amount of tokens to unstake
     */
    function unstake(uint256 _amount) public whenNotPaused nonReentrant {
        UserData storage user = userData[msg.sender];

        if (_amount > user.stakedAmount) revert StakingContract_IncorrectInputValue(); // check if staked amount is greater than unstake amount
        if (_amount == 0 || _amount < i_minimalAmount) revert StakingContract_IncorrectInputValue();

        if (user.lastTimeStamp != 0 && block.timestamp < user.lastTimeStamp + MINIMAL_TIME_BETWEEN) {
            revert StakingContract_TooEarly();
        }

        _calculateRewards(msg.sender);

        userData[msg.sender].stakedAmount = userData[msg.sender].stakedAmount - _amount;

        ///@notice update total staked amount
        s_totalStakedAmount = s_totalStakedAmount - _amount;

        i_stakingToken.safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @notice Enables users to claim their accumulated rewards
     * @dev Calculates latest rewards, resets user reward balance to zero,
     *      and transfers reward tokens from contract to user
     * @dev Guards against reentrancy and checks for sufficient contract balance
     * @dev Can only be called when contract is not paused
     * @dev Reverts if user has no rewards to claim
     */
    function claimRewards() public whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256 protocolBalance = i_stakingToken.balanceOf(address(this));

        if (userData[sender].lastTimeStamp == 0) revert StakingContract_ClaimFailed();

        _calculateRewards(sender);

        uint256 rewardsToSend = userData[sender].rewards;

        if (rewardsToSend == 0) revert StakingContract_NoRewardsAvailable();

        userData[sender].rewards = 0;

        s_totalRewardsAmount = s_totalRewardsAmount - rewardsToSend;

        if (protocolBalance >= rewardsToSend) {
            i_stakingToken.safeTransfer(sender, rewardsToSend);
        } else {
            revert StakingContract_ClaimFailed();
        }

        emit RewardsClaimed(sender, rewardsToSend);
    }

    /**
     * @notice Permits the owner to halt all staking operations in case of emergency
     * @dev Calls OpenZeppelin's _pause function
     * @dev Can only be called by the contract owner when contract is not already paused
     * @dev When paused, stake, unstake, and claimRewards functions cannot be called
     */
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Permits the owner to resume staking operations after a pause
     * @dev Calls OpenZeppelin's _unpause function
     * @dev Can only be called by the contract owner when contract is paused
     */
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    /**
     * @notice Function for admin to change the reward distribution rate
     * @dev Calculates all pending rewards with the old rate before changing
     * @dev Emits a RewardRateChanged event with old and new rates
     * @dev Can only be called by the contract owner
     * @param _rewardRate The new reward rate to be set
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        uint256 oldRate = s_rewardRate;

        if (_rewardRate == oldRate || _rewardRate == 0) revert StakingContract_IncorrectInputValue();
        //calculate with the old rate
        _calculateAllRewards();

        //update to new rate
        s_rewardRate = _rewardRate;

        emit RewardRateChanged(oldRate, s_rewardRate);
    }

    /*//////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates rewards for a user based on staking time and amount
     * @dev Uses formula: rewards = stakedAmount * rewardRate * timeElapsed / BASIS_POINTS
     * @dev Updates user's reward balance and lastTimeStamp
     * @dev Emits a RewardsCalculated event with updated reward value
     * @dev Skips calculation if user has no stake or timestamp is not set
     * @param _user Address of the user to calculate rewards for
     */
    function _calculateRewards(address _user) internal {

        UserData storage user = userData[_user];

        ///@dev skip if user's stake is zero
        if (user.stakedAmount == 0 || user.lastTimeStamp == 0) {
            return;
        }

        ///@dev time passed since last calculations
        uint256 passedTime = block.timestamp - user.lastTimeStamp;

        uint256 newRewards = (user.stakedAmount * s_rewardRate * passedTime) / BASIS_POINTS;

        user.rewards = user.rewards + newRewards;
        s_totalRewardsAmount = s_totalRewardsAmount + newRewards;

        user.lastTimeStamp = block.timestamp;

        emit RewardsCalculated(_user, user.rewards);
    }

    /**
     * @notice Updates rewards for all stakers in the contract
     * @dev Iterates through the stakers array and calculates rewards for each
     * @dev Only processes addresses with active stakes (stakedAmount > 0)
     * @dev Used when changing reward rates to ensure all users get correct rewards
     */
    function _calculateAllRewards() internal {
        for (uint256 i = 0; i < stakers.length; i++) {
            address stakersAddress = stakers[i];

            if (userData[stakersAddress].stakedAmount > 0) {
                _calculateRewards(stakersAddress);
            }
        }
    }

    /**
     * @notice Checks if the contract has enough reserves to cover staked amounts plus a safety buffer
     * @dev Reverts with ContractInsufficientBalance if reserves are inadequate
     * @dev The minimal reserve is calculated as a percentage of total staked tokens
     * @param _amount Amount being unstaked/handled in the current transaction
     */
    function _checkReserves(uint256 _amount) internal view {
        uint256 minimalReserveAmount = (s_totalStakedAmount * MINIMAL_CONTRACT_BALANCE_PERCENTAGE) / BASIS_POINTS;

        uint256 currentBalance = i_stakingToken.balanceOf(address(this));

        if (currentBalance < (s_totalStakedAmount - _amount) + minimalReserveAmount) {
            revert StakingContract_ContractInsufficientBalance();
        }
    }

    /*//////////////////////////////////////////////////////
                    GETTER FUNCTIONS
    //////////////////////////////////////////////////////*/

    /**
     * @notice Gets the amount of tokens staked by a specific user
     * @param _staker Address of the staker to query
     * @return uint256 The amount of tokens staked by the user
     */
    function getStakedBalanceOf(address _staker) public view returns (uint256) {
        return userData[_staker].stakedAmount;
    }

    /**
     * @notice Gets the timestamp of the last reward calculation for a user
     * @param _staker Address of the staker to query
     * @return uint256 The timestamp when rewards were last calculated for the user
     */
    function getStakeTimestamp(address _staker) public view returns (uint256) {
        return userData[_staker].lastTimeStamp;
    }

    /**
     * @notice Gets the total number of addresses that have staked in the contract
     * @dev Returns the length of the stakers array
     * @return uint256 The number of unique staker addresses
     */
    function getStakersLength() public view returns (uint256) {
        return stakers.length;
    }

    /**
     * @notice Gets the current unclaimed rewards for a specific user
     * @dev Does not calculate new rewards, only returns the stored value
     * @param _staker Address of the staker to query
     * @return uint256 The amount of unclaimed rewards for the user
     */
    function getRewards(address _staker) public view returns (uint256) {
        return userData[_staker].rewards;
    }

    /**
     * @notice Gets the total amount of pending rewards for all users
     * @return uint256 The cumulative amount of all rewards to distribute
     */
    function getTotalRewardsAmount() public view returns (uint256) {
        return s_totalRewardsAmount;
    }
}
