// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {ScoutToken} from "../src/TokenERC20.sol";
import {DeployTokenERC20} from "../script/DeployProtocol.s.sol";

contract TokenTest is Test {
    ScoutToken scoutToken;

    address public owner;
    address public userOne;
    address public userTwo;
    address public userThree;
    address public userFour;

    uint256 public initial_supply;

    function setUp() public {
        owner = msg.sender;
        userOne = makeAddr("userone");
        userTwo = makeAddr("usertwo");
        userThree = makeAddr("userthree");
        userFour = makeAddr("userfour");

        initial_supply = 1000;

        hoax(owner, 100 ether);
        DeployTokenERC20 deployToken = new DeployTokenERC20();
        scoutToken = deployToken.runTokenERC20(initial_supply);
    }

/*//////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////*/

    function test_Minting1000Tokens() public view {

        assertEq(
            scoutToken.totalSupply(),
            initial_supply * (10 ** scoutToken.decimals()),
            "Different amount of minted token than expected!"
        );
    }





/*//////////////////////////////////////////////////////////////////
                            
//////////////////////////////////////////////////////////////////*/
}
