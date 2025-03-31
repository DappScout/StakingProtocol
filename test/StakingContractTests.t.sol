//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, Vm, console} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {ScoutToken} from "../src/TokenERC20.sol";
import {DeployStakingContract} from "../script/DeployProtocol.s.sol";
import {DeployTokenERC20} from "../script/DeployProtocol.s.sol";

contract StakingProtocolTest is Test {
    StakingContract stakingContract;
    ScoutToken tokenContract;

    address public owner;
    address public userOne;
    address public userTwo;

    address public userThree;
    address public userFour;

    uint256 public constant DEFAULT_TOKEN_SUPPLY = 10000;
    uint256 public constant DEFAULT_STAKE_AMOUNT = 0;

    ///@dev values is updated contractBalance()
    uint256 public contractBalance;

    function setUp() public {
        owner = msg.sender;
        userOne = makeAddr("userone");
        userTwo = makeAddr("usertwo");
        userThree = makeAddr("userthree");
        userFour = makeAddr("userfour");

        deployContracts(DEFAULT_TOKEN_SUPPLY, DEFAULT_STAKE_AMOUNT);
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Helper functions/////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function deployContracts(uint256 _initialSupply, uint256 _minimalStakeAmount) public {
        DeployTokenERC20 deployTokenERC20 = new DeployTokenERC20();
        tokenContract = deployTokenERC20.runTokenERC20(_initialSupply);

        DeployStakingContract deployStakingContract = new DeployStakingContract();
        stakingContract = deployStakingContract.runStakingProtocol(owner, address(tokenContract), _minimalStakeAmount);
    }

    function getContractBalance() public returns (uint256 _contractBalance) {
        contractBalance = stakingContract.i_stakingToken().balanceOf(address(stakingContract));

        return contractBalance;
    }

    function getContractBalanceOf() public view returns (uint256) {
        return stakingContract.i_stakingToken().balanceOf(address(stakingContract));
    }

    function getStakerBalance(address user) public view returns (uint256) {
        return stakingContract.i_stakingToken().balanceOf(user);
    }

    function userPause(address user) public {
        vm.startPrank(user);
        stakingContract.pause();
        vm.stopPrank();
    }

    function userUnpause(address _user) public {
        vm.startPrank(_user);
        stakingContract.unpause();
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

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Pause tests/////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testOwnerPausingTheContract() public {
        //  Scenario: Owner pauses the contract
        //   Given the Staking contract is active
        //   When the owner calls "pause()"
        //   Then the contract should log a "Paused" event
        //   And any subsequent calls to "stake", "unstake", or "claimRewards" should revert with "Contract is paused"

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        vm.recordLogs();
        //act

        userPause(owner);

        //check
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1, "One log was expected!");
        bytes32 expectedEvent = keccak256("Paused(address)");
        assertEq(entries[0].topics[0], expectedEvent, "Paused event was not emmited!");

        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testOwnerUnpausingTheContract() public {
        //setup
        vm.recordLogs();
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        userPause(owner);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act

        userUnpause(owner);

        //check

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2, "Two logs were expected!");
        bytes32 expectedEvent1 = keccak256("Paused(address)");
        bytes32 expectedEvent2 = keccak256("Unpaused(address)");
        assertEq(entries[0].topics[0], expectedEvent1, "Paused event was not emmited!");
        assertEq(entries[1].topics[0], expectedEvent2, "Paused event was not emmited!");
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

    function testUserPausingTheContract() public {
        // Scenario: Owner unpauses the contract
        //   Given the Staking contract is paused
        //   When the owner calls "unpause()"
        //   Then the contract should log an "Unpaused" event
        //   And normal operations (stake, unstake, claimRewards) should resume successfully

        //setup
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        vm.recordLogs();

        //act
        vm.expectRevert();
        userPause(userOne);

        //check
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

    function testUserUnpausingTheContract() public {
        //setup
        vm.recordLogs();
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        userPause(owner);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");

        //act
        vm.expectRevert();
        userUnpause(userOne);

        //check
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1, "One log was expected!");
        bytes32 expectedEvent = keccak256("Paused(address)");
        assertEq(entries[0].topics[0], expectedEvent, "Paused event was not emmited!");

        assertEq(stakingContract.paused(), true, "Protocol is unpaused!");
    }

    //When paused, functions like stake, unstake, and claimRewards should revert.
    //Only privileged functions (such as unpause) should operate while the contract is paused.

    function testStakeWhilePaused() public {}

    function testUnstakeWhilePaused() public {}

    function testClaimRewardsWhilePaused() public {}

    function testPauseWhilePaused() public {}

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Staking tests///////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testUserStakeTokens() public {
        // Scenario: User stakes tokens successfully
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   And a deployed Staking contract with a reward rate of 0.1% per block
        //   When Alice approves the Staking contract to spend 100 tokens
        //   And Alice calls "stake(100)" on the Staking contract
        //   Then the contract should log a "Staked" event with (Alice, 100)
        //   And Alice's staked balance should be 100 tokens
        //   And the total staked amount in the contract should increase by 100 tokens

        //setup

        console.log(getContractBalanceOf());
        assertEq(getContractBalanceOf(), 0, "Balance is not zero!");

        mintToken(userOne, 100);
        assertEq(tokenContract.balanceOf(userOne), 100, "User's balance is not 100!");

        //act

        approveUser(userOne, address(stakingContract), 100);

        vm.recordLogs();

        vm.prank(userOne);
        stakingContract.stake(100);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //check

        assertEq(tokenContract.balanceOf(userOne), 0, "User's balance is not zero!");

        // check - events
        assertEq(entries.length, 2, "Emission of one event was expected!");
        bytes32 expectedEvent1 = keccak256("Staked(address,uint256)");
        assertEq(entries[1].topics[0], expectedEvent1, "Staked event was not emitted!");

        address stakerAddress = address(uint160(uint256(entries[1].topics[1])));
        assertEq(stakerAddress, userOne, "Wrong staker address in event!");

        uint256 stakedAmount = abi.decode(entries[1].data, (uint256));
        assertEq(stakedAmount, 100, "Wrong amount in event!");

        // check - accounting
    }

    function testUserStakeWithZeroAmount() public {
        // Scenario: User stakes 0 tokens
        //   Given a deployed Token contract with an initial token balance for user "Alice"
        //   When Alice calls "stake(0)" on the Staking contract
        //   Then the contract should revert with "StakingContract_WrongAmountGiven()"
        //   And Alice's staked balance should be 0 tokens
        //   And the total staked amount in the contract should not change
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Unstaking tests///////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function testUserUnstakeTokens() public {
        // Scenario: User unstakes tokens successfully
        //   Given Alice has previously staked 100 tokens
        //   When Alice calls "unstake(50)" on the Staking contract
        //   Then the contract should log an "Unstaked" event with (Alice, 50)
        //   And Alice's staked balance should decrease to 50 tokens
        //   And the total staked amount should decrease by 50 tokens
    
        //setup
        mintToken(userOne, 100);
        assertEq(tokenContract.balanceOf(userOne), 100, "User's balance is not 100!");
        approveUser(userOne, address(stakingContract), 100);
        vm.prank(userOne);
        stakingContract.stake(100);
        vm.recordLogs();

        //act
        vm.prank(userOne);
        stakingContract.unstake(50);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //check

        assertEq(tokenContract.balanceOf(userOne), 50, "User's balance is not 50!");
        assertEq(stakingContract.getStakedBalance(userOne), 50, "User's stake is not 50!");
        //assertEq(stakingContract.s_totalStakedAmount(), 50, "Total staked amount is not 50!");

        // check - events
        assertEq(entries.length, 2, "Emission of one event was expected!");
        bytes32 expectedEvent1 = keccak256("Unstaked(address,uint256)");
        assertEq(entries[1].topics[0], expectedEvent1, "Unstaked event was not emitted!");

        address stakerAddress = address(uint160(uint256(entries[1].topics[1])));
        assertEq(stakerAddress, userOne, "Wrong staker address in event!");

        uint256 unstakedAmount = abi.decode(entries[1].data, (uint256));
        assertEq(unstakedAmount, 50, "Wrong amount in event!");
    }

}
