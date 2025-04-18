//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, Vm} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../../src/StakingContract.sol";
import {ScoutToken} from "../../src/TokenERC20.sol";
import {DeployStakingContract} from "../../script/DeployProtocol.s.sol";
import {DeployTokenERC20} from "../../script/DeployProtocol.s.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract StakingProtocolTest is Test {
    StakingContract stakingContract;
    ScoutToken tokenContract;

    address public owner;
    address public userOne;
    address public userTwo;

    address public userThree;
    address public userFour;

    uint256 public constant DEFAULT_TOKEN_SUPPLY = 10000;
    uint256 public constant DEFAULT_MINIMAL_AMOUNT = 10 * 15;
    uint256 public constant DECIMALS = 10 ** 18;

    ///@dev values is updated contractBalance()
    uint256 public contractBalance;

    uint256 public minimalReserveDivisor;

    uint256 public stakedAmount;

    uint256 public minimalContractAmount;

    /*//////////////////////////////////////////////////////
                    EVENTS
    //////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event RewardsCalculated(address indexed user, uint256 reward);
    event RewardRateChanged(uint256 oldRate, uint256 newRate);
    event Unpaused(address account);
    event Paused(address account);

    function setUp() public virtual {
        owner = msg.sender;
        userOne = makeAddr("userone");
        userTwo = makeAddr("usertwo");
        userThree = makeAddr("userthree");
        userFour = makeAddr("userfour");

        deployContracts(DEFAULT_TOKEN_SUPPLY, DEFAULT_MINIMAL_AMOUNT);
        minimalReserveDivisor = DECIMALS / stakingContract.MINIMAL_CONTRACT_BALANCE_PERCENTAGE();
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Helper functions////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function deployContracts(uint256 _initialSupply, uint256 _minimalStakeAmount) public {
        DeployTokenERC20 deployTokenERC20 = new DeployTokenERC20();
        tokenContract = deployTokenERC20.runTokenERC20(_initialSupply);

        DeployStakingContract deployStakingContract = new DeployStakingContract();
        stakingContract = deployStakingContract.runStakingProtocol(owner, address(tokenContract), _minimalStakeAmount);
    }

    function getContractBalanceOf() public view returns (uint256) {
        return stakingContract.i_stakingToken().balanceOf(address(stakingContract));
    }

    function getStakerBalance(address user) public view returns (uint256) {
        return stakingContract.i_stakingToken().balanceOf(user);
    }

    function _setPauseState(address user, bool _paused) public {
        vm.startPrank(user);
        if (_paused) {
            stakingContract.pause();
        } else {
            stakingContract.unpause();
        }
        vm.stopPrank();
    }

    function mintToken(address _user, uint256 _value) public {
        vm.prank(owner);
        tokenContract.mint(_user, _value);
    }

    function approveUser(address _user, address _spender, uint256 _amount) public {
        vm.prank(_user);
        tokenContract.approve(_spender, _amount);
    }

    function _setupStakedUser(address _user, uint256 _amount) public {
        mintToken(_user, _amount);
        approveUser(_user, address(stakingContract), _amount);
        vm.prank(_user);
        stakingContract.stake(_amount);
    }

    function _calculateNewRewards(address _user) public view returns (uint256 _rewards) {
        uint256 timePassed = block.timestamp - stakingContract.getStakeTimestamp(_user);

        uint256 expectedRewards = (
            stakingContract.getStakedBalanceOf(_user) * stakingContract.s_rewardRate() * timePassed
        ) / stakingContract.BASIS_POINTS();

        return expectedRewards;
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Helper Modifiers////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    modifier setStakeAmount(uint256 _stakeAmount) {
        stakedAmount = _stakeAmount * DECIMALS;
        minimalContractAmount = stakedAmount / minimalReserveDivisor;
        mintToken(address(stakingContract), stakedAmount + minimalContractAmount);
        _;
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Pause tests/////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testPause_ByOwner() public {
        //  Scenario: Owner pauses the contract
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the contract should be paused

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");

        //act
        _setPauseState(owner, true);

        //check
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testPause_ByNonOwner() public {
        //  Scenario: Non-owner pauses the contract
        //   Given the Staking contract is active
        //   When a non-owner calls "pause()"
        //   Then the call should revert

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");

        //act
        vm.expectRevert();
        _setPauseState(userOne, true);

        //check
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

    function testPause_ByOwner_EmitsEvent() public {
        // Scenario: Pausing contract emits event
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the contract should log a "Paused" event

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");

        //act
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);
        _setPauseState(owner, true);
        //check
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testPause_PausesStake() public {
        // Scenario: Pausing contract pauses stake
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the stake should revert

        //setup
        uint256 _amount = 100 * DECIMALS;
        mintToken(address(stakingContract), _amount);

        mintToken(userOne, _amount);
        approveUser(userOne, address(stakingContract), _amount);

        //act
        _setPauseState(owner, true);

        vm.expectRevert();
        stakingContract.stake(_amount);
        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), 0, "User has staked!");
    }

    function testPause_PausesUnstake() public setStakeAmount(100) {
        // Scenario: Pausing contract pauses unstake
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the unstake should revert

        //setup
        _setupStakedUser(userOne, stakedAmount);
        //act
        _setPauseState(owner, true);

        vm.prank(userOne);
        vm.expectRevert();
        stakingContract.unstake(stakedAmount);
        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User has unstaked!");
    }

    function testPause_PausesClaim() public setStakeAmount(100) {
        // Scenario: Pausing contract pauses claim
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the claim should revert

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getStakerBalance(userOne), 0, "User has not staked!");
        //act
        _setPauseState(owner, true);

        vm.prank(userOne);
        vm.expectRevert();
        stakingContract.claimRewards();
        //check
    }

    function testPause_WhenAlreadyPaused() public {
        // Scenario: Pausing contract pauses itself
        //   Given the Staking contract is paused
        //   When the owner calls again "pause()"
        //   Then the call should revert

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        //act
        vm.expectRevert();
        _setPauseState(owner, true);
        //check
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testPause_AllowsSetRewardRate() public {
        // Scenario: Setting reward rate is allowed when paused
        //   Given the Staking contract is paused
        //   When the owner calls "setRewardRate()"
        //   Then the call should succeed

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        //act
        vm.expectEmit(false, false, false, false);
        emit RewardRateChanged(stakingContract.s_rewardRate(), 2 * stakingContract.s_rewardRate());
        vm.startPrank(owner);
        stakingContract.setRewardRate(2 * stakingContract.s_rewardRate());
        vm.stopPrank();

        //check
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testPause_AllowsViewFunctions() public setStakeAmount(100) {
        // Scenario: View functions work when paused
        //   Given the Staking contract is paused and user has staked tokens
        //   When view functions are called
        //   Then they should work normally

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User has not staked!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "View function does not work!");
        assertEq(stakingContract.getStakersLength(), 1, "View function does not work!");
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Unpause tests/////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testUnpause_ByOwner() public {
        // Scenario: Owner unpauses the contract
        //   Given the Staking contract is paused
        //   When the owner calls "unpause()"
        //   Then the contract should be unpaused

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act

        _setPauseState(owner, false);

        //check
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

    function testUnpause_ByNonOwner() public {
        // Scenario: Non-owner unpauses the contract
        //   Given the Staking contract is paused
        //   When a non-owner calls "unpause()"
        //   Then the call should revert

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act
        vm.expectRevert();
        _setPauseState(userOne, false);

        //check
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testUnpause_EmitsEvent() public {
        // Scenario: Unpausing contract emits event
        //   Given the Staking contract is paused
        //   When the owner calls "unpause()"
        //   Then the contract should log an "Unpaused" event

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);
        _setPauseState(owner, false);

        //check
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

    function testUnpause_RestoresStakeFunctionality() public {
        // Scenario: Unpausing contract restores functionality
        //   Given the Staking contract is paused
        //   When the owner calls "unpause()"
        //   Then the contract should be unpaused
        //   And stake should work again

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act

        _setPauseState(owner, false);
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setupStakedUser(userOne, stakeAmount);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User has not staked!");
    }

    function testUnpause_RestoresUnstakeFunctionality() public {
        // Scenario: Unpausing contract restores functionality
        //   Given the Staking contract is paused
        //   When the owner calls "unpause()"
        //   Then the contract should be unpaused
        //   And unstake should work again

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        _setupStakedUser(userOne, stakeAmount);

        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        vm.warp(block.timestamp + 1 hours);

        //act

        _setPauseState(owner, false);
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        vm.prank(userOne);
        stakingContract.unstake(stakeAmount);

        //check
        assertEq(getStakerBalance(userOne), stakeAmount, "User has not unstaked!");
    }

    function testUnpause_RestoresClaimFunctionality() public {
        // Scenario: Unpausing contract restores functionality
        //   Given the Staking contract is paused
        //   When the owner calls "unpause()"
        //   Then claim rewards should work again

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        uint256 additionalBalance = 100 * DECIMALS;
        mintToken(address(stakingContract), additionalBalance);

        _setupStakedUser(userOne, stakeAmount);

        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        vm.warp(block.timestamp + 1 hours);
        //act

        _setPauseState(owner, false);
        assertEq(stakingContract.paused(), false, "Protocol is paused!");

        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User has not claimed rewards!");
    }

    function testUnpause_WhenAlreadyUnpaused() public {
        // Scenario: Unpausing contract when already unpaused
        //   Given the Staking contract is unpaused
        //   When the owner calls "unpause()"
        //   Then the call should revert

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        //act
        vm.expectRevert();
        _setPauseState(owner, false);
        //check
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Staking tests///////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testStake_UpdatesUserBalance() public setStakeAmount(100) {
        // Scenario: User's balance updates after staking
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then Alice's staked balance should be 100 tokens

        //setup
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not 100!");
    }

    function testStake_UpdatesContractBalance() public setStakeAmount(100) {
        // Scenario: Contract's balance updates after staking
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then the contract's balance should be 100 tokens

        //setup
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check
        // We should see the initial reserve amount + the staked amount after staking
        assertEq(
            getContractBalanceOf(),
            stakedAmount + minimalContractAmount + stakedAmount,
            "Contract's balance is incorrect!"
        );
    }

    function testStake_UpdatesTotalStakedAmount() public setStakeAmount(100) {
        //  Scenario: Staking updates total staked amount
        //    Given a deployed Token contract with an initial token balance for user "Alice"
        //    And a deployed Staking contract with a reward rate of 0.1% per block
        //    When Alice approves the Staking contract to spend 100 tokens
        //    And Alice calls "stake(100)" on the Staking contract
        //    Then the total staked amount should be 100 tokens

        //setup
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.s_totalStakedAmount(), stakedAmount, "Total staked amount is not 100!");
    }

    function testStake_EmitsEvent() public {
        // Scenario: Staking emits event
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then the contract should log a "Staked" event with (Alice, 100)

        //setup

        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(address(stakingContract), stakedAmount);

        // assertEq(getContractBalanceOf(), 0, "Balance is not zero!");
        mintToken(userOne, stakedAmount);
        assertEq(tokenContract.balanceOf(userOne), stakedAmount, "User's balance is not 100!");
        approveUser(userOne, address(stakingContract), stakedAmount);

        //act & check

        vm.expectEmit(true, false, false, false);
        emit Staked(userOne, stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_UpdatesStakeTimestamp() public setStakeAmount(100) {
        // Scenario: User's stake timestamp updates after first staking
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then Alice's stake timestamp should be updated

        //setup
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not updated!");
    }

    function testStake_WithMinimalAmount() public setStakeAmount(100) {
        // Scenario: User stakes minimal amount
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a minimal stake amount of 100 tokens
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then Alice's staked balance should be 100 tokens

        //setup
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act & check
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not 100!");
    }

    function testStake_BelowMinimalAmount_Reverts() public {
        // Scenario: User stakes below minimal amount
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a minimal stake amount of 100 tokens
        //   When Alice approves the Staking contract to spend 99 tokens
        //   And Alice calls "stake(99)" on the Staking contract
        //   Then the contract should revert with "StakingContract_IncorrectInputValue()"

        //setup
        uint256 minimalStakeAmount = 100;
        deployContracts(DEFAULT_TOKEN_SUPPLY, minimalStakeAmount);

        uint256 stakedAmount = 99;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_BigAmount() public setStakeAmount(100_000) {
        // Scenario: User stakes a big amount
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a balance of 0 tokens
        //   And Alice calls "stake(100_000_000_000)" on the Staking contract
        //   Then Alice's staked balance should be 100_000_000_000 tokens

        //setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act & check
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not 100_000_000_000!");
    }

    function testStake_WithoutApproval() public setStakeAmount(100) {
        // Scenario: User stakes tokens without approval
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // When Alice calls "stake(100)" on the Staking contract
        // Then the call should revert

        //setup
        mintToken(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)", address(stakingContract), 0, stakedAmount
            )
        );
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_WithPartialApproval() public setStakeAmount(100) {
        // Scenario: User stakes tokens with partial approval
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And Alice has approved 50 tokens for the Staking contract
        // When Alice calls "stake(100)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 approveAmount = 50;
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), approveAmount);
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)",
                address(stakingContract),
                approveAmount,
                stakedAmount
            )
        );
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_WithInsufficientBalance() public {
        // Scenario: User stakes tokens with insufficient balance
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And Alice has approved 100 tokens for the Staking contract
        // When Alice calls "stake(100)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount / 2);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");
        approveUser(userOne, address(stakingContract), stakedAmount);

        //act & check
        vm.expectRevert();
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_MultipleTimes_InShortIntervals() public setStakeAmount(100) {
        // Scenario: User stakes tokens multiple times in short period
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And Alice has approved 100 tokens for the Staking contract multiple times
        // When Alice calls second "stake(100)" on the Staking contract
        // Then call should revert

        //setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act & check
        _setupStakedUser(userOne, stakedAmount);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_ToEarly()"));
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_MultipleTimes_InLongIntervals() public {
        // Scenario: User stakes tokens multiple times in long period
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And Alice has approved 100 tokens for the Staking contract multiple times
        // When Alice calls "stake(100)" on the Staking contract multiple times
        // Then every call should be successful
        // And Alice's staked balance should be 1000 tokens

        //setup
        uint256 intervals = 10;
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(address(stakingContract), stakedAmount);

        //act
        for (uint256 i = 0; i < intervals; i++) {
            vm.warp(block.timestamp + stakingContract.MINIMAL_TIME_BETWEEN());
            _setupStakedUser(userOne, stakedAmount);
        }

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount * intervals, "User's stake is not 1000!");
    }

    function testStake_MultipleUsers() public {
        // Scenario: Multiple users stake tokens
        // Given a deployed Token contract with an initial token balance for user multiple users
        // And a deployed Staking contract with a balance of 0 tokens
        // When multiple users call "stake(100)" on the Staking contract in short periods between calls
        // Then each user's staked balance should be 100 tokens
        // And the total staked amount should be 1000 tokens

        //setup
        uint160 numberOfUsers = 10;
        uint160 firstUser = 1;
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(address(stakingContract), stakedAmount);

        //act
        for (uint160 i = firstUser; i <= numberOfUsers; i++) {
            _setupStakedUser(address(i), stakedAmount);
            assertEq(stakingContract.getStakedBalanceOf(address(i)), stakedAmount, "User's stake is not 100");
        }

        //check
        assertEq(
            getContractBalanceOf(),
            (stakedAmount * 2) + (stakedAmount * numberOfUsers),
            "Contract balance is not correct!"
        );
    }

    function testStake_WithZeroAmount() public {
        // Scenario: User stakes 0 tokens
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And a deployed Staking contract with a balance of 0 tokens
        // When Alice calls "stake(0)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 stakedAmount = 0;
        mintToken(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_RevertIfContractPaused() public {
        // Scenario: User stakes tokens when contract is paused
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And a deployed Staking contract with a balance of 0 tokens
        // And the contract is paused by the owner
        // When Alice calls "stake(100)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");
        _setPauseState(owner, true);

        //act & check
        vm.expectRevert();
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_UpdatesStakersArray() public setStakeAmount(100) {
        // Scenario: User stakes tokens
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And a deployed Staking contract with a balance of 0 tokens
        // When Alice calls "stake(100)" on the Staking contract
        // Then Alice's address should be added to the stakers array

        //setup
        assertEq(getContractBalanceOf(), stakedAmount + minimalContractAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakersLength(), 1, "Stakers array length is not 1!");
        assertEq(stakingContract.stakers(0), userOne, "Staker is not userOne!");
    }

    function testStake_RevertWhenIssuficientReserves() public {
        // Scenario: User stakes tokens when contract balance is not enough to cover minimal reserve
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And a deployed Staking contract with a balance of 0 tokens
        // When Alice calls "stake(100)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_ContractInsufficientBalance()"));
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Unstaking tests///////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testUnstake_ByUser() public setStakeAmount(100) {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract

        // setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(50 * DECIMALS);
    }

    function testUnstake_ChangesUserBalance() public setStakeAmount(100) {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then Alice's staked balance should decrease to 50 tokens

        // setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount / 2, "User's stake is not 50!");
    }

    function testUnstake_ChangesContractBalance() public setStakeAmount(100) {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then contract balance should decrease by the unstaked amount

        // setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        // record balance before unstaking
        uint256 balanceBefore = getContractBalanceOf();

        //act
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        //check
        assertEq(getContractBalanceOf(), balanceBefore - (stakedAmount / 2), "Contract's balance is incorrect!");
    }

    function testUnstake_RevertIfNotEnoughStaked() public setStakeAmount(100) {
        // Scenario: User unstakes larger amount than staked
        //   Given Alice has previously staked 100 tokens
        //   And contract balance is 100 tokens
        //   When Alice calls "unstake(200)" on the Staking contract
        //   Then call should revert

        //setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.unstake(stakedAmount * 2);
    }

    function testUnstake_WithZeroAmount() public setStakeAmount(100) {
        // Scenario: User unstakes 0 tokens
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(0)" on the Staking contract
        //   Then call should revert

        //setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.unstake(0);
    }

    function testUnstake_WithMinimalAmount() public {
        // Scenario: User unstakes minimal amount
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(99)" on the Staking contract
        //   Then Alice's staked balance should be reduced appropriately

        //setup
        uint256 minimalStakeAmount = 99 * DECIMALS;
        uint256 stakedAmount = 100 * DECIMALS;

        deployContracts(DEFAULT_TOKEN_SUPPLY, minimalStakeAmount);

        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);

        uint256 balanceBefore = getContractBalanceOf();
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(minimalStakeAmount);

        assertEq(
            stakingContract.getStakedBalanceOf(userOne), stakedAmount - minimalStakeAmount, "User's stake is not 1!"
        );
        assertEq(getContractBalanceOf(), balanceBefore - minimalStakeAmount, "Contract balance is incorrect!");
    }

    function testUnstake_MoreThanStaked() public setStakeAmount(100) {
        // Scenario: User unstakes more than staked
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(101)" on the Staking contract
        //   Then call should revert

        //setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.unstake(stakedAmount + 1);
    }

    function testUnstake_WithMoreThanStaked() public setStakeAmount(100) {
        // Scenario: User unstakes more than staked
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(101)" on the Staking contract
        //   Then call should revert

        //setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.unstake(stakedAmount + 1);
    }

    function testUnstake_EmitsEvent() public setStakeAmount(100) {
        // Scenario: Succesful unstake emits event
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(100)" on the Staking contract
        //   Then "Unstaked" event should be emitted

        // setuo
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.expectEmit(true, false, false, false);
        emit Unstaked(userOne, stakedAmount);
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount);
    }

    function testUnstake_WithoutPreviousStake() public {
        // Scenario: User unstakes without previous stake
        //   Given Alice has not staked any tokens
        //   When Alice calls "unstake(100)" on the Staking contract
        //   Then call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.unstake(stakedAmount);
    }

    function testUnstake_HalfOfStake() public setStakeAmount(100) {
        ///  Scenario: User unstakes half of their stake
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then Alice's staked balance should decrease to 50 tokens
        //   And contract balance should decrease accordingly

        // Setup
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);

        // Record balance before unstaking
        uint256 balanceBefore = getContractBalanceOf();
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        // Verify balances
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount / 2, "User's stake is not 50!");
        assertEq(getContractBalanceOf(), balanceBefore - (stakedAmount / 2), "Contract balance is incorrect!");
    }

    function testUnstake_AllOfStake() public setStakeAmount(100) {
        ///  Scenario: User unstakes all of their stake
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(100)" on the Staking contract
        //   Then Alice's staked balance should decrease to 0 tokens
        //   And contract balance should decrease to 0 tokens

        // Setup staking
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        // Get balance before unstaking
        uint256 contractBalanceBefore = getContractBalanceOf();

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), 0, "User's stake is not 0!");
        assertEq(
            getContractBalanceOf(), contractBalanceBefore - stakedAmount, "Contract balance incorrect after unstake!"
        );
    }

    function testUnstake_WithRewards() public setStakeAmount(100) {
        // Scenario: User unstakes with rewards
        // Given Alice has previously staked 100 tokens
        // And after 1 hour
        // When Alice calls "unstake(100)" on the Staking contract
        // Then Alice's staked balance should decrease to 0 tokens
        // And contract balance should decrease to 0 tokens
        // And Alice's rewards should not change

        // Setup staking
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);

        // Let time pass to accumulate rewards
        vm.warp(block.timestamp + 1 hours);

        // Get balance before unstaking and calculate expected rewards
        uint256 contractBalanceBefore = getContractBalanceOf();
        uint256 rewards = _calculateNewRewards(userOne);

        // Act
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount);

        // check
        assertEq(stakingContract.getStakedBalanceOf(userOne), 0, "User's stake is not 0!");
        assertEq(
            getContractBalanceOf(), contractBalanceBefore - stakedAmount, "Contract balance incorrect after unstake!"
        );
        assertEq(stakingContract.getRewards(userOne), rewards, "User's rewards shouldn't be 0!");
    }

    function testUnstake_MultipleTimes_WithShortBreaks() public setStakeAmount(100) {
        // Scenario: User unstakes multiple times in short period
        //   Given Alice has previously staked 100 tokens
        //   And after 1 hour
        //   When Alice calls "unstake(50)" twice on the Staking contract in short period
        //   Then first call should succeed
        //   And second call should revert

        //setup
        _setupStakedUser(userOne, stakedAmount);

        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.startPrank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        vm.expectRevert(abi.encodeWithSignature("StakingContract_ToEarly()"));
        stakingContract.unstake(stakedAmount / 2);
        vm.stopPrank();

        //check
        assertEq(
            stakingContract.getStakedBalanceOf(userOne), stakedAmount - (stakedAmount / 2), "User's stake is not 50!"
        );
    }

    function testUnstake_MultipleTimes_WithLongBreaks() public {
        // Scenario: User unstakes multiple times in long period
        //   Given Alice has previously staked 100 tokens
        //   After 1 hour
        //   When Alice calls "unstake(10)" 5 times on the Staking contract in long period
        //   Then all calls should succeed

        //setup
        uint256 intervals = 10;
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);

        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "Alice stake is not correct");
        vm.warp(block.timestamp + 1 hours);

        //act
        for (uint256 i = 0; i < intervals / 2; i++) {
            vm.startPrank(userOne);
            stakingContract.unstake(stakedAmount / intervals);
            vm.stopPrank();
            vm.warp(block.timestamp + 1 hours);
        }

        //check
        assertEq(getContractBalanceOf(), stakedAmount + (stakedAmount / 2), "Contract balance is incorrect!");
    }

    function testUnstake_ByMultipleUsers() public setStakeAmount(100) {
        // Scenario: Multiple users unstake their stakes
        //   Given multiple users have previously staked tokens
        //   When they call "unstake()" on the Staking contract
        //   Then their staked balances should decrease
        //   And amount of tokens unstaked should be equal to the amount previously staked
        //   And contract balance should be equal to the initial mint

        //setup
        uint256 intervals = 10;
        uint256 unstakeAmount = stakedAmount / 2;
        address[] memory users = new address[](intervals);

        for (uint256 i = 0; i < intervals; i++) {
            users[i] = makeAddr(Strings.toString(i));
            mintToken(address(stakingContract), stakedAmount);
            _setupStakedUser(users[i], stakedAmount);
            assertEq(stakingContract.getStakedBalanceOf(users[i]), stakedAmount, "User's stake is not correct");
        }

        vm.warp(block.timestamp + 1 hours);

        //act
        for (uint256 i = 0; i < intervals; i++) {
            vm.startPrank(users[i]);
            stakingContract.unstake(unstakeAmount);
            assertEq(
                stakingContract.getStakedBalanceOf(users[i]),
                stakedAmount - unstakeAmount,
                "User's stake is not correct"
            );
            vm.stopPrank();
        }

        //check
        assertEq(
            getContractBalanceOf(),
            ((stakedAmount * intervals) * 2) - (unstakeAmount * intervals) + stakedAmount + minimalContractAmount,
            "Contract balance is not correct!"
        );
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Claim Rewards tests/////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testClaimRewards_WithZeroRewards() public setStakeAmount(100) {
        // Scenario: User claims rewards with zero rewards
        //   Given the Staking contract is active
        //   When the user calls "claimRewards()"
        //   Then the call should revert with correct error

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not correct");

        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_NoRewardsAvailable()"));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_WhilePaused() public setStakeAmount(100) {
        // Scenario: User claims rewards while contract is paused
        //   Given the Staking contract is paused
        //   When the user calls "claimRewards()"
        //   Then call should revert

        //setup
        _setupStakedUser(userOne, stakedAmount);
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol is not paused!");

        //check
        vm.expectRevert();
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_ByUser() public setStakeAmount(100) {
        // Scenario: User claims rewards
        //   Given the user has staked tokens
        //   When the user calls "claimRewards()"
        //   Then the user should receive the rewards

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not correct");
        vm.warp(block.timestamp + 1 hours);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_ResetsRewards() public setStakeAmount(100) {
        // Scenario: User claims rewards
        // Given the User earned some rewards
        // When the user calls "claimRewards()"
        // Then the user should receive the rewards
        // And the user's rewards should be reset

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not correct");
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        vm.warp(block.timestamp + 1 hours);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
    }

    function testClaimRewards_TransfersCorrectAmount() public setStakeAmount(100) {
        // Scenario: Correct amount of rewards is transferred
        // Given the user has staked tokens
        // And rewards have been calculated
        // When the user calls "claimRewards()"
        // Then the user should receive the correct amount of rewards

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not correct");
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        vm.warp(block.timestamp + 1 hours);

        //act
        uint256 amountBefore = getStakerBalance(userOne);
        uint256 newRewards = _calculateNewRewards(userOne);

        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        assertEq(getStakerBalance(userOne), amountBefore + newRewards, "User's balance is not correct");
    }

    function testClaimRewards_ByNonStaker() public {
        //Scenario: User claims rewards by non-staker
        //Given the user has not staked tokens
        //When the user calls "claimRewards()"
        //Then the call should revert

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_ClaimFailed()"));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_AfterContractUnpaused() public setStakeAmount(100) {
        //Scenario: User claims rewards after contract unpaused
        //Given the contract is paused and then unpaused
        //When the user calls "claimRewards()"
        //Then the user should be able to claim rewards

        //setup
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        _setPauseState(owner, true);
        _setPauseState(owner, false);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();

        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
    }

    function testClaimRewards_AfterMultipleStakes() public setStakeAmount(100) {
        //Scenario: User claims rewards after multiple stakes
        //Given the user has staked tokens multiple times
        //When the user calls "claimRewards()" after multiple stakes
        //Then the user should receive the rewards

        //setup
        // Add extra tokens for multiple stakes and rewards
        mintToken(address(stakingContract), stakedAmount * 3);

        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        // Add tokens for second stake
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        // Add tokens for third stake
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        uint256 rewardsBefore = stakingContract.getRewards(userOne);
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
    }

    function testClaimRewards_UpdatesTotalRewardsAmount() public setStakeAmount(100) {
        //Scenario: User claims rewards updates total rewards amount
        //Given the user has staked tokens
        //And time passed
        //When the user calls "claimRewards()"
        //Then the total rewards amount should be updated to 0

        //setup
        _setupStakedUser(userOne, stakedAmount);
        uint256 oldRewards = stakingContract.getTotalRewardsAmount();
        vm.warp(block.timestamp + 1 hours);

        //act
        uint256 newRewards = _calculateNewRewards(userOne);
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getTotalRewardsAmount(), oldRewards, "User's rewards is not correct");
    }

    function testClaimRewards_EmitEvent() public setStakeAmount(100) {
        // Scenario: User claims rewards emit event
        //   Given the user has staked tokens
        //   When the user calls "claimRewards()"
        //   Then the "RewardsClaimed" event should be emitted

        //setup
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(userOne, _calculateNewRewards(userOne));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_WhenContractBalanceIsNotEnough() public setStakeAmount(100) {
        // Scenario: User claims rewards when contract balance is not enough
        //   Given the user has staked tokens
        //   And contract balance is less than rewards
        //   When the user calls "claimRewards()"
        //   Then call should revert

        //setup
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 300000 days);

        //act

        //check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_ClaimFailed()"));
        stakingContract.claimRewards();
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Calculate Rewards tests/////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testCalculateRewards_ByUser() public setStakeAmount(100) {
        // Scenario: User calculates rewards
        //   Given the protocol is active
        //   When the user that previously staked calls "stake()"
        //   Then the user's rewards should be calculated

        //setup

        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);

        vm.warp(block.timestamp + 1 days);

        //act

        uint256 usersRewards = _calculateNewRewards(userOne) + stakingContract.getRewards(userOne);

        _setupStakedUser(userOne, stakedAmount);
        //check
        assertEq(stakingContract.getRewards(userOne), usersRewards, "User's rewards is not correct");
    }

    function testCalculateRewards_ChangeLastTimeStamp() public setStakeAmount(100) {
        // Scenario: User calculates rewards
        //   Given the user has staked tokens
        //   When the user calls "claimRewards()" after 1 hour
        //   Then the user should receive the expected rewards

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not correct");
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");

        vm.warp(block.timestamp + 1 hours);

        //act
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");
    }

    function testCalculateRewards_SkippedWhenNewUser() public setStakeAmount(100) {
        // Scenario: User calculates rewards
        //   Given the user did not stake tokens
        //   When the user calls "stake()"
        //   Then the user rewards calculations should be skipped

        //setup
        _setupStakedUser(userOne, stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not correct");
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");

        vm.warp(block.timestamp + 1 hours);

        //act
        vm.prank(userOne);
        stakingContract.claimRewards();
        //check
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");
    }

    function testCalculateRewards_EmitsEvent() public setStakeAmount(100) {
        // Scenario: User calculates rewards emits event
        //   Given the user has staked tokens
        //   When the user calls "claimRewards()"
        //   Then the "RewardsCalculated" event should be emitted

        //setup
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.expectEmit(true, false, false, true);
        emit RewardsCalculated(userOne, _calculateNewRewards(userOne));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testCalculateRewards_AfterPartialUnstake() public setStakeAmount(100) {
        // Scenario: User calculates rewards after partial unstake
        //   Given the user has staked tokens
        //   And the user unstakes a portion of their stake
        //   When the user calls "claimRewards()"
        //   Then the user should receive the correct amount of rewards

        //setup
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        uint256 amountBefore = getStakerBalance(userOne);
        uint256 newRewards = _calculateNewRewards(userOne);

        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        //act
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        assertEq(getStakerBalance(userOne), newRewards + (stakedAmount / 2), "User's balance is not correct");
    }

    function testCalculateRewards_AfterMultipleStakes() public setStakeAmount(100) {
        // Scenario: User calculates rewards after multiple stakes
        //   Given the user has staked tokens multiple times
        //   When the user calls "claimRewards()" after multiple stakes
        //   Then the user should receive the correct amount of rewards

        //setup
        uint256 calculatedRewards;

        for (uint256 i = 0; i < 5; i++) {
            mintToken(address(stakingContract), stakedAmount);
            _setupStakedUser(userOne, stakedAmount);
            vm.warp(block.timestamp + 1 hours);
            calculatedRewards += _calculateNewRewards(userOne);
        }

        //act
        uint256 amount = getStakerBalance(userOne);

        vm.prank(userOne);
        stakingContract.claimRewards();
        calculatedRewards += _calculateNewRewards(userOne);
        //check
        assertEq(getStakerBalance(userOne), calculatedRewards, "User's rewards is not correct");
    }

    function testCalculateRewards_BigAmount() public setStakeAmount(1000000000) {
        // Scenario: User calculates rewards with big amount
        //   Given the user has staked a large amount of tokens
        //   When the user calls "claimRewards()"
        //   Then the user should receive the correct amount of rewards

        //setup
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        uint256 amount = getStakerBalance(userOne);
        uint256 newRewards = _calculateNewRewards(userOne);

        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        assertEq(getStakerBalance(userOne), amount + newRewards, "User's balance is not correct");
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Changing RewardRate/////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testChangeRate_ByOwner() public {
        // Scenario: Owner changes reward rate
        // Given the owner has the right to change reward rate
        // When the owner calls "changeRewardRate()"
        // Then the reward rate should be changed

        //setup
        uint256 newRate = 2000000000;

        //act
        vm.prank(owner);
        stakingContract.setRewardRate(newRate);

        //check
        assertEq(stakingContract.s_rewardRate(), newRate, "Reward rate is not correct");
    }

    function testChangeRate_ByNonOwner() public {
        // Scenario: Non-owner cannot change reward rate
        // Given the owner has the right to change reward rate
        // When the non-owner calls "changeRewardRate()"
        // Then the call should revert

        //setup
        uint256 newRate = 2000000000;
        vm.prank(userOne);
        vm.expectRevert();
        stakingContract.setRewardRate(newRate);
    }

    function testChangeRate_EmitsEvent() public {
        //Scenario: Reward rate change emits event
        //Given the owner has the right to change reward rate
        //When the owner calls "changeRewardRate()"
        //Then the "RewardRateChanged" event should be emitted

        //setup
        uint256 newRate = 2000000000;

        //act & check
        vm.expectEmit(false, false, false, true);
        emit RewardRateChanged(stakingContract.s_rewardRate(), newRate);
        vm.prank(owner);
        stakingContract.setRewardRate(newRate);
    }

    function testChangeRate_ToTheSameRate() public {
        // Scenario: Owner cannot change reward rate to the same value
        // Given the owner has the right to change reward rate
        // When the owner calls "changeRewardRate()" with the same rate
        // Then the call should revert

        //setup
        uint256 newRate = 1000000000;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.setRewardRate(newRate);
    }

    function testChangeRate_CalculatesRewards() public setStakeAmount(100) {
        // Scenario: Rewards for all users are calculated when changing reward rate
        // Given the owner has the right to change reward rate
        // When the owner calls "changeRewardRate()"
        // Then the rewards for all users should be calculated

        //setup
        uint256 newRate = 2000000000;

        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        uint256 calculatedRewards = _calculateNewRewards(userOne);
        vm.prank(owner);
        stakingContract.setRewardRate(newRate);

        //check
        assertEq(stakingContract.getRewards(userOne), calculatedRewards, "User's rewards is not correct");
    }

    function testChangeRate_CalculatesRewardsForAllUsers() public setStakeAmount(100) {
        // Scenario: Rewards for all users are calculated when changing reward rate
        // Given the owner has the right to change reward rate
        // When the owner calls "changeRewardRate()"
        // Then the rewards for all users should be calculated

        //setup

        uint256 newRate = 2000000000;
        uint256 calculatedRewards;

        uint160 firstUser = 1;
        uint160 numberOfUsers = 10;

        mintToken(address(stakingContract), stakedAmount * numberOfUsers);

        for (uint160 i = firstUser; i < numberOfUsers; i++) {
            _setupStakedUser(address(i), stakedAmount);
        }

        vm.warp(block.timestamp + 1 hours);

        //act & check
        ///@dev calculate rewards with old rate
        for (uint160 i = firstUser; i < numberOfUsers; i++) {
            calculatedRewards += _calculateNewRewards(address(i));
        }
        vm.prank(owner);
        stakingContract.setRewardRate(newRate);

        //check
        assertEq(stakingContract.s_totalRewardsAmount(), calculatedRewards, "User's rewards is not correct");
        assertEq(stakingContract.s_rewardRate(), newRate, "Reward rate is not correct");
    }

    function testChangeRate_ToZero() public {
        // Scenario: Owner cannot set reward rate to zero
        // Given the owner has the right to change reward rate
        // When the owner calls "changeRewardRate()" with zero rate
        // Then the call should revert

        //setup
        uint256 newRate = 0;
        uint256 defaultRate = stakingContract.s_rewardRate();
        //act
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_IncorrectInputValue()"));
        stakingContract.setRewardRate(newRate);
        vm.stopPrank();
        //check
        assertEq(stakingContract.s_rewardRate(), defaultRate, "Reward rate is not correct");
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Integration tests///////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testIntegration_Stake_Unstake_Claim() public {
        //setup

        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act

        _setupStakedUser(userOne, stakeAmount);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(userOne);
        stakingContract.unstake(stakeAmount);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(userOne);
        stakingContract.claimRewards();
        //check

        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not 0!");
    }

    function testIntegration_Stake_PartialUnstake_Stake() public {
        //setup

        uint256 stakeAmount = 100 * DECIMALS;
        uint256 calculatedRewards;
        uint256 partialAmount = stakeAmount / 2;

        mintToken(address(stakingContract), stakeAmount);

        //act

        _setupStakedUser(userOne, stakeAmount);

        vm.warp(block.timestamp + 1 hours);

        calculatedRewards += _calculateNewRewards(userOne);
        vm.prank(userOne);
        stakingContract.unstake(partialAmount);

        vm.warp(block.timestamp + 1 hours);

        calculatedRewards += _calculateNewRewards(userOne);
        vm.prank(userOne);
        stakingContract.claimRewards();
        //check

        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not 0!");
        assertEq(stakingContract.s_totalStakedAmount(), partialAmount, "Total staked amount is not correct");
        assertEq(getStakerBalance(userOne), (partialAmount) + calculatedRewards, "User's balance is not correct");
    }

    function testIntegration_MultipleUsers_Stake_Unstake_Claim() public {
        //setup

        uint256 stakeAmount = 100 * DECIMALS;
        uint256 calculatedRewards;
        uint256 partialAmount = stakeAmount / 2;
        uint160 numberOfUsers = 10;
        uint160 firstUser = 1;
        uint256[] memory calculatedRewardsPerUser = new uint256[](numberOfUsers);

        mintToken(address(stakingContract), stakeAmount);

        //act
        for (uint160 i = firstUser; i <= numberOfUsers; i++) {
            _setupStakedUser(address(i), stakeAmount);
        }

        vm.warp(block.timestamp + 1 hours);

        for (uint160 i = firstUser; i <= numberOfUsers; i++) {
            calculatedRewardsPerUser[i - 1] += _calculateNewRewards(address(i));
            vm.prank(address(i));
            stakingContract.unstake(partialAmount);
        }

        vm.warp(block.timestamp + 1 hours);

        for (uint160 i = firstUser; i <= numberOfUsers; i++) {
            calculatedRewardsPerUser[i - 1] += _calculateNewRewards(address(i));
            vm.prank(address(i));
            stakingContract.claimRewards();
            assertEq(stakingContract.getRewards(address(i)), 0, "User's rewards is not 0!");
            assertEq(
                getStakerBalance(address(i)),
                stakeAmount - partialAmount + calculatedRewardsPerUser[i - 1],
                "User's balance is not correct"
            );
        }

        //check
        assertEq(
            stakingContract.s_totalStakedAmount(), partialAmount * numberOfUsers, "Total staked amount is not correct"
        );
    }

    function testIntegration_Stake_Unstake_Claim_AfterOneYear() public {
        //setup

        uint256 calculatedRewards;
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act

        _setupStakedUser(userOne, stakeAmount);

        vm.warp(block.timestamp + 365 days);

        calculatedRewards += _calculateNewRewards(userOne);
        vm.prank(userOne);
        stakingContract.unstake(stakeAmount);

        vm.warp(block.timestamp + 365 days);

        vm.prank(userOne);
        stakingContract.claimRewards();
        //check

        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not 0!");
        assertEq(getStakerBalance(userOne), stakeAmount + calculatedRewards, "User's balance is not correct");
    }
}
