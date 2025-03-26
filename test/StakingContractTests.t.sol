//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test,Vm} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {DeployStakingContract} from "../script/DeployProtocol.s.sol";

contract StakingProtocolTest is Test{

    StakingContract stakingContract;

    address public owner;
    address public userOne;
    address public userTwo;
    address public userThree;
    address public userFour;

    function setUp() public{
    
        owner = msg.sender;
        userOne = makeAddr("userone");
        userTwo = makeAddr("usertwo");
        userThree = makeAddr("userthree");
        userFour = makeAddr("userfour");


        DeployStakingContract deployStakingContract = new DeployStakingContract();
        stakingContract = deployStakingContract.runStakingProtocol(owner);


    }

    function userPause(address user) public{
        vm.startPrank(user);
        stakingContract.pause();
        vm.stopPrank();
    }


    function userUnpause(address user) public{
        vm.startPrank(user);
        stakingContract.unpause();
        vm.stopPrank();
    }


    /*
    Scenario: Owner pauses the contract
    Given the Staking contract is active
    When the owner calls "pause()"
    Then the contract should log a "Paused" event
    And any subsequent calls to "stake", "unstake", or "claimRewards" should revert with "Contract is paused"
    */
    function testOwnerPausingTheContract() public{

        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        
        //act

        userPause(owner);

        //check
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
    }

    function testOwnerUnpausingTheContract() public{

        assertEq(stakingContract.paused(), false, "Protocol is paused!");
        userPause(owner);
        assertEq(stakingContract.paused(), true, "Protocol isnt paused!");
        
        //act

        userUnpause(owner);

        //check
        assertEq(stakingContract.paused(), false, "Protocol is paused!");
    }

}
