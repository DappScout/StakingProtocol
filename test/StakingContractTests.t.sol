//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, Vm} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {DeployStakingContract} from "../script/DeployProtocol.s.sol";

contract StakingProtocolTest is Test {
    StakingContract stakingContract;

    address public owner;
    address public userOne;
    address public userTwo;
    address public userThree;
    address public userFour;

    function setUp() public {
        owner = msg.sender;
        userOne = makeAddr("userone");
        userTwo = makeAddr("usertwo");
        userThree = makeAddr("userthree");
        userFour = makeAddr("userfour");

        DeployStakingContract deployStakingContract = new DeployStakingContract();
        stakingContract = deployStakingContract.runStakingProtocol(owner);
    }

    /*///////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////Pause tests/////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    function userPause(address user) public {
        vm.startPrank(user);
        stakingContract.pause();
        vm.stopPrank();
    }

    function userUnpause(address user) public {
        vm.startPrank(user);
        stakingContract.unpause();
        vm.stopPrank();
    }

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

    function testUserStakeTokens() public{
    // Scenario: User stakes tokens successfully
    //   Given a deployed Token contract with an initial token balance for user "Alice"
    //   And a deployed Staking contract with a reward rate of 0.1% per block
    //   When Alice approves the Staking contract to spend 100 tokens
    //   And Alice calls "stake(100)" on the Staking contract
    //   Then the contract should log a "Staked" event with (Alice, 100)
    //   And Alice's staked balance should be 100 tokens
    //   And the total staked amount in the contract should increase by 100 tokens

    

        
    }
}
