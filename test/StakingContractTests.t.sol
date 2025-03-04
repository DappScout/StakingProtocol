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

    


}
