//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, Vm, console} from "lib/forge-std/src/Test.sol";
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
    uint256 public constant DEFAULT_STAKE_AMOUNT = 10 * 15;
    uint256 public constant DECIMALS = 10 ** 18;

    ///@dev values is updated contractBalance()
    uint256 public contractBalance;

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

    function setUp() public {
        owner = msg.sender;
        userOne = makeAddr("userone");
        userTwo = makeAddr("usertwo");
        userThree = makeAddr("userthree");
        userFour = makeAddr("userfour");

        deployContracts(DEFAULT_TOKEN_SUPPLY, DEFAULT_STAKE_AMOUNT);
        //mintToken(address(stakingContract), 9 * DECIMALS);
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

    function _calculateNewRewards(address _user) public returns (uint256 _rewards) {
        uint256 timePassed = block.timestamp - stakingContract.getStakeTimestamp(_user);

        uint256 expectedRewards = (
            stakingContract.getStakedBalanceOf(_user) * stakingContract.s_rewardRate() * timePassed
        ) / stakingContract.BASIS_POINTS();

        return expectedRewards;
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Helper Modifiers////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

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

    function testPause_PausesUnstake() public {
        // Scenario: Pausing contract pauses unstake
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the unstake should revert

        //setup
        uint256 _amount = 100 * DECIMALS;
        mintToken(address(stakingContract), _amount);
        _setupStakedUser(userOne, _amount);
        //act
        _setPauseState(owner, true);

        vm.expectRevert();
        stakingContract.unstake(_amount);
        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), _amount, "User has unstaked!");
    }

    function testPause_PausesClaim() public {
        // Scenario: Pausing contract pauses claim
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the claim should revert

        //setup
        uint256 _amount = 100 * DECIMALS;
        mintToken(address(stakingContract), _amount);
        _setupStakedUser(userOne, _amount);
        assertEq(getStakerBalance(userOne), 0, "User has not staked!");
        //act
        _setPauseState(owner, true);

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

    function testPause_AllowsViewFunctions() public {
        // Scenario: View functions work when paused
        //   Given the Staking contract is paused and user has staked tokens
        //   When view functions are called
        //   Then they should work normally

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User has not staked!");
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "View function does not work!");
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

    function testStake_UpdatesUserBalance() public {
        // Scenario: User's balance updates after staking
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then Alice's staked balance should be 100 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);

        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act

        _setupStakedUser(userOne, stakedAmount);

        //check

        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not 100!");
    }

    function testStake_UpdatesContractBalance() public {
        // Scenario: Contract's balance updates after staking
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then the contract's balance should be 100 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);

        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check

        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract's balance is incorrect!");
    }

    function testStake_UpdatesTotalStakedAmount() public {
        //  Scenario: Staking updates total staked amount
        //    Given a deployed Token contract with an initial token balance for user "Alice"
        //    And a deployed Staking contract with a reward rate of 0.1% per block
        //    When Alice approves the Staking contract to spend 100 tokens
        //    And Alice calls "stake(100)" on the Staking contract
        //    Then the total staked amount should be 100 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);

        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");
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

    function testStake_UpdatesStakeTimestamp() public {
        // Scenario: User's stake timestamp updates after first staking
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then Alice's stake timestamp should be updated

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);

        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");
        //act

        _setupStakedUser(userOne, stakedAmount);

        //check

        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not updated!");
    }

    function testStake_WithMinimalAmount() public {
        // Scenario: User stakes minimal amount
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a minimal stake amount of 100 tokens
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then Alice's staked balance should be 100 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);

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
        //   Then the contract should revert with "StakingContract_WrongAmountGiven()"

        //setup
        uint256 minimalStakeAmount = 100;
        deployContracts(DEFAULT_TOKEN_SUPPLY, minimalStakeAmount);

        uint256 stakedAmount = 99;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_BigAmount() public {
        // Scenario: User stakes a big amount
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a balance of 0 tokens
        //   And Alice calls "stake(100_000_000_000)" on the Staking contract
        //   Then Alice's staked balance should be 100_000_000_000 tokens

        //setup
        uint256 stakedAmount = 100_000 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount, "User's stake is not 100_000_000_000!");
    }

    function testStake_WithoutApproval() public {
        // Scenario: User stakes tokens without approval
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // When Alice calls "stake(100)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)", address(stakingContract), 0, stakedAmount
            )
        );
        vm.prank(userOne);
        stakingContract.stake(stakedAmount);
    }

    function testStake_WithPartialApproval() public {
        // Scenario: User stakes tokens with partial approval
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And Alice has approved 100 tokens for the Staking contract
        // When Alice calls "stake(50)" on the Staking contract
        // Then the call should revert

        //setup
        uint256 aproveAmount = 50;
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), aproveAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientAllowance(address,uint256,uint256)",
                address(stakingContract),
                aproveAmount,
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

    function testStake_MultipleTimes_InShortIntervals() public {
        // Scenario: User stakes tokens multiple times in short period
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And Alice has approved 100 tokens for the Staking contract multiple times
        // When Alice calls second "stake(100)" on the Staking contract
        // Then call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(userOne, stakedAmount);
        approveUser(userOne, address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act & check
        _setupStakedUser(userOne, stakedAmount);
        vm.expectRevert();
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
        uint256 intervals = 10;
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        mintToken(address(stakingContract), stakedAmount);

        //act
        for (uint256 i = 0; i < intervals; i++) {
            address user = makeAddr(Strings.toString(i));
            _setupStakedUser(user, stakedAmount);
            assertEq(stakingContract.getStakedBalanceOf(user), stakedAmount, "User's stake is not 100");
        }

        //check
        assertEq(
            getContractBalanceOf(), (stakedAmount * 2) + (stakedAmount * intervals), "Contract balance is not correct!"
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
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
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

    function testStake_UpdatesStakersArray() public {
        // Scenario: User stakes tokens
        // Given a deployed Token contract with an initial token balance for user "Alice"
        // And a deployed Staking contract with a balance of 0 tokens
        // When Alice calls "stake(100)" on the Staking contract
        // Then Alice's address should be added to the stakers array

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount, "Initial contract balance is incorrect!");

        //act
        _setupStakedUser(userOne, stakedAmount);

        //check
        assertEq(stakingContract.getStakersLength(), 1, "Stakers array length is not 1!");
        assertEq(stakingContract.stakers(0), userOne, "Staker is not userOne!");
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Unstaking tests///////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testUnstake_ByUser() public {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(50 * DECIMALS);
    }

    function testUnstake_ChangesUserBalance() public {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then Alice's staked balance should decrease to 50 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);
        //act & check
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        //check
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount / 2, "User's stake is not 50!");
    }

    function testUnstake_ChangesContractBalance() public {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then contract balance should decrease to 50 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);

        //check
        assertEq(getContractBalanceOf(), stakedAmount + (stakedAmount / 2), "Contract's balance is incorrect!");
    }

    function testUnstake_RevertIfNotEnoughStaked() public {
        // Scenario: User unstakes larger amount than staked
        //   Given Alice has previously staked 100 tokens
        //   And contract balance is 100 tokens
        //   When Alice calls "unstake(200)" on the Staking contract
        //   Then call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
        stakingContract.unstake(stakedAmount * 2);
    }

    function testUnstake_WithZeroAmount() public {
        // Scenario: User unstakes 0 tokens
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(0)" on the Staking contract
        //   Then call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
        stakingContract.unstake(0);
    }

    function testUnstake_WithMinimalAmount() public {
        // Scenario: User unstakes minimal amount
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(99)" on the Staking contract
        //   Then Alice's staked balance should stay 100 tokens
        //   And contract balance should not decrease

        //setup

        uint256 minimalStakeAmount = 99 * DECIMALS;
        deployContracts(DEFAULT_TOKEN_SUPPLY, minimalStakeAmount);

        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(minimalStakeAmount);
        assertEq(
            stakingContract.getStakedBalanceOf(userOne), stakedAmount - minimalStakeAmount, "User's stake is not 1!"
        );
        assertEq(
            getContractBalanceOf(), stakedAmount + (stakedAmount - minimalStakeAmount), "Contract balance is incorrect!"
        );
    }

    function testUnstake_MoreThanStaked() public {
        // Scenario: User unstakes more than staked
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(101)" on the Staking contract
        //   Then call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
        stakingContract.unstake(stakedAmount + 1);
    }

    function testUnstake_WithMoreThanStaked() public {
        // Scenario: User unstakes more than staked
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(101)" on the Staking contract
        //   Then call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
        stakingContract.unstake(stakedAmount + 1);
    }

    function testUnstake_EmitsEvent() public {
        // Scenario: Succesful unstake emits event
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(100)" on the Staking contract
        //   Then "Unstaked" event should be emitted

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.expectEmit(true, true, false, false);
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
        vm.expectRevert(abi.encodeWithSignature("StakingContract_WrongAmountGiven()"));
        stakingContract.unstake(stakedAmount);
    }

    function testUnstake_HalfOfStake() public {
        ///  Scenario: User unstakes half of their stake
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then Alice's staked balance should decrease to 50 tokens
        //   And contract balance should decrease to 50 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount / 2);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakedAmount / 2, "User's stake is not 50!");
        assertEq(getContractBalanceOf(), stakedAmount + (stakedAmount / 2), "Contract balance is incorrect!");
    }

    function testUnstake_AllOfStake() public {
        ///  Scenario: User unstakes all of their stake
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(100)" on the Staking contract
        //   Then Alice's staked balance should decrease to 0 tokens
        //   And contract balance should decrease to 0 tokens

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.prank(userOne);
        stakingContract.unstake(stakedAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), 0, "User's stake is not 0!");
        assertEq(getContractBalanceOf(), stakedAmount, "Contract balance should be equal to the initial mint!");
    }

    function testUnstake_WithRewards() public {}

    function testUnstake_MultipleTimes_WithShortBreaks() public {
        // Scenario: User unstakes multiple times in short period
        //   Given Alice has previously staked 100 tokens
        //   And after 1 hour
        //   When Alice calls "unstake(50)" twice on the Staking contract in short period
        //   Then first call should succeed
        //   And second call should revert

        //setup
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        _setupStakedUser(userOne, stakedAmount);
        assertEq(getContractBalanceOf(), stakedAmount * 2, "Contract balance is incorrect!");
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

    function testUnstake_ByMultipleUsers() public {
        // Scenario: Multiple users unstake their stakes
        //   Given multiple users have previously staked tokens
        //   When they call "unstake()" on the Staking contract
        //   Then their staked balances should decrease
        //   And amount of tokens unstaked should be equal to the amount previously staked
        //   And contract balance should be equal to the initial mint

        //setup
        uint256 intervals = 10;
        uint256 stakedAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakedAmount);
        uint256 unstakeAmount = stakedAmount / 2;
        address[] memory users = new address[](intervals);

        for (uint256 i = 0; i < intervals; i++) {
            users[i] = makeAddr(Strings.toString(i));
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
            (stakedAmount + stakedAmount * intervals) - (unstakeAmount * intervals),
            "Contract balance is not correct!"
        );
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Claim Rewards tests/////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testClaimRewards_WithZeroRewards() public {
        // Scenario: User claims rewards with zero rewards
        //   Given the Staking contract is active
        //   When the user calls "claimRewards()"
        //   Then the call should revert with correct error

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User's stake is not correct");

        //act & check
        vm.expectRevert(abi.encodeWithSignature("StakingContract_NoRewardsAvailable()"));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_WhilePaused() public {
        // Scenario: User claims rewards while contract is paused
        //   Given the Staking contract is paused
        //   When the user calls "claimRewards()"
        //   Then call should revert

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act
        _setupStakedUser(userOne, stakeAmount);
        _setPauseState(owner, true);
        assertEq(stakingContract.paused(), true, "Protocol is not paused!");

        //check
        vm.expectRevert();
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_ByUser() public {
        // Scenario: User claims rewards
        // Given the User earned some rewards
        // When the user calls "claimRewards()"
        // Then the user should receive the rewards

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act
        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User's stake is not correct");
        vm.warp(block.timestamp + 1 hours);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_ResetsRewards() public {
        // Scenario: User claims rewards
        // Given the User earned some rewards
        // When the user calls "claimRewards()"
        // Then the user should receive the rewards
        // And the user's rewards should be reset

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act
        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User's stake is not correct");
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        vm.warp(block.timestamp + 1 hours);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
    }

    function testClaimRewards_TransfersCorrectAmount() public {
        // Scenario: Correct amount of rewards is transferred
        // Given the user has staked tokens
        // And rewards have been calculated
        // When the user calls "claimRewards()"
        // Then the user should receive the correct amount of rewards

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User's stake is not correct");
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

    function testClaimRewards_AfterContractUnpaused() public {
        //Scenario: User claims rewards after contract is unpaused
        //Given the Staking contract is paused
        //And user has staked tokens
        //And contract is unpaused
        //When the user calls "claimRewards()"
        //Then the user should receive the rewards

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        _setPauseState(owner, true);
        _setPauseState(owner, false);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();

        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
    }

    function testClaimRewards_AfterMultipleStakes() public {
        //Scenario: User claims rewards after multiple stakes
        //Given the user has staked tokens multiple times
        //When the user calls "claimRewards()" after multiple stakes
        //Then the user should receive the rewards

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        for (uint256 i = 0; i < 5; i++) {
            _setupStakedUser(userOne, stakeAmount);
            vm.warp(block.timestamp + 1 hours);
        }
        //act
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
    }

    function testClaimRewards_UpdatesTotalRewardsAmount() public {
        //Scenario: User claims rewards updates total rewards amount
        //Given the user has staked tokens
        //When the user calls "claimRewards()"
        //Then the total rewards amount should be updated

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        vm.warp(block.timestamp + 1 hours);

        //act
        uint256 newRewards = _calculateNewRewards(userOne);
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getTotalRewardsAmount(), newRewards, "User's rewards is not correct");
    }

    function testClaimRewards_EmitEvent() public {
        // Scenario: User claims rewards emits event
        // Given the user has staked tokens
        // When the user calls "claimRewards()"
        // Then the "RewardsClaimed" event should be emitted

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(userOne, _calculateNewRewards(userOne));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testClaimRewards_WhenContractBalanceIsNotEnough() public {
        // Scenario: User claims rewards when contract balance is not enough
        //   Given the user has staked tokens
        //   And contract balance is less than rewards
        //   When the user calls "claimRewards()"
        //   Then call should revert

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        _setupStakedUser(userOne, stakeAmount);
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

    function testCalculateRewards_ByUser() public {
        // Scenario: User calculates rewards
        //   Given the protocol is active
        //   When the user that previously staked calls "stake()"
        //   Then the user's rewards should be calculated

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        _setupStakedUser(userOne, stakeAmount);

        vm.warp(block.timestamp + 1 days);

        //act

        uint256 usersRewards = _calculateNewRewards(userOne) + stakingContract.getRewards(userOne);

        _setupStakedUser(userOne, stakeAmount);
        //check
        assertEq(stakingContract.getRewards(userOne), usersRewards, "User's rewards is not correct");
    }

    function testCalculateRewards_ChangeLastTimeStamp() public {
        // Scenario: User calculates rewards
        //   Given the user has staked tokens
        //   When the user calls "claimRewards()" after 1 hour
        //   Then the user should receive the expected rewards

        //setup

        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act
        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User's stake is not correct");
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");

        vm.warp(block.timestamp + 1 hours);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");
    }

    function testCalculateRewards_SkippedWhenNewUser() public {
        // Scenario: User calculates rewards
        //   Given the user did not stake tokens
        //   When the user calls "stake()"
        //   Then the user rewards calculations should be skipped

        //setup

        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        //act
        _setupStakedUser(userOne, stakeAmount);
        assertEq(stakingContract.getStakedBalanceOf(userOne), stakeAmount, "User's stake is not correct");
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");

        vm.warp(block.timestamp + 1 hours);

        //check
        vm.prank(userOne);
        stakingContract.claimRewards();
        assertEq(stakingContract.getStakeTimestamp(userOne), block.timestamp, "User's stake timestamp is not correct");
    }

    function testCalculateRewards_EmitsEvent() public {
        // Scenario: User calculates rewards emits event
        //   Given the user has staked tokens
        //   When the user calls "claimRewards()"
        //   Then the "RewardsCalculated" event should be emitted

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        vm.warp(block.timestamp + 1 hours);

        //act & check
        vm.expectEmit(true, false, false, true);
        emit RewardsCalculated(userOne, _calculateNewRewards(userOne));
        vm.prank(userOne);
        stakingContract.claimRewards();
    }

    function testCalculateRewards_AfterPartialUnstake() public {
        // Scenario: User calculates rewards after partial unstake
        //   Given the user has staked tokens
        //   And the user unstakes a portion of their stake
        //   When the user calls "claimRewards()"
        //   Then the user should receive the correct amount of rewards

        //setup
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
        vm.warp(block.timestamp + 1 hours);

        uint256 amountBefore = getStakerBalance(userOne);
        uint256 newRewards = _calculateNewRewards(userOne);

        vm.prank(userOne);
        stakingContract.unstake(stakeAmount / 2);

        //act
        vm.prank(userOne);
        stakingContract.claimRewards();

        //check
        assertEq(stakingContract.getRewards(userOne), 0, "User's rewards is not correct");
        assertEq(getStakerBalance(userOne), newRewards + (stakeAmount / 2), "User's balance is not correct");
    }

    function testCalculateRewards_AfterMultipleStakes() public {
        // Scenario: User calculates rewards after multiple stakes
        //   Given the user has staked tokens multiple times
        //   When the user calls "claimRewards()" after multiple stakes
        //   Then the user should receive the correct amount of rewards

        //setup
        uint256 calculatedRewards;
        uint256 stakeAmount = 100 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);

        for (uint256 i = 0; i < 5; i++) {
            _setupStakedUser(userOne, stakeAmount);
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

    function testCalculateRewards_BigAmount() public {
        // Scenario: User calculates rewards with big amount
        //   Given the user has staked a large amount of tokens
        //   When the user calls "claimRewards()"
        //   Then the user should receive the correct amount of rewards

        //setup
        uint256 stakeAmount = 1000000000 * DECIMALS;
        mintToken(address(stakingContract), stakeAmount);
        _setupStakedUser(userOne, stakeAmount);
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
    /////////////////////////////////Events tests////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/
}
