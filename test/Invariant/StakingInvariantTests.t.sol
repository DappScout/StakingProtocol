//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, Vm, console} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../../src/StakingContract.sol";
import {ScoutToken} from "../../src/TokenERC20.sol";
import {DeployStakingContract} from "../../script/DeployProtocol.s.sol";
import {DeployTokenERC20} from "../../script/DeployProtocol.s.sol";

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

    function getContractBalance() public returns (uint256) {
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
    /////////////////////////////////Invariant tests/////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////*/

    ///@dev Total staked amount must always equal the sum of all individual user stakes

    function testCheckInvariants() public {
        ///@dev Total staked amount must always equal the sum of all individual user stakes
        uint256 calculatedTotalStakedAmount;

        for (uint256 i = 0; i < stakingContract.getStakersLength(); i++) {
            calculatedTotalStakedAmount += stakingContract.getStakedBalanceOf(stakingContract.stakers(i));
        }

        assertEq(calculatedTotalStakedAmount, stakingContract.s_totalStakedAmount(), "TotalStakedAmount mismatch!");

        ///@dev Contract's token balance must always be ≥ total staked amount + unclaimed rewards

        assertTrue(getContractBalance() >= calculatedTotalStakedAmount + stakingContract.s_totalRewardsAmount());
    }

    function stakeWithChecks(address _user, uint256 _amount) public {
        vm.prank(_user);
        stakingContract.stake(_amount);

        testCheckInvariants();
    }
}
