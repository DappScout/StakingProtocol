// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "lib/forge-std/src/Test.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {ScoutToken} from "../src/TokenERC20.sol";
import {DeployTokenERC20} from "../script/DeployProtocol.s.sol";

contract TokenTest is Test {
    ScoutToken scoutToken;

    address public Owner;
    address public userOne;
    address public userTwo;
    address public userThree;
    address public userFour;

    uint256 public initial_supply;

    function setUp() public {
        Owner = address(1);
        userOne = address(2);
        userTwo = address(3);
        userThree = address(4);
        userFour = address(5);

        initial_supply = 1000;

        vm.deal(Owner, 100 ether);
        vm.prank(Owner);
        scoutToken = new ScoutToken(initial_supply);
    }

    function test_Minting1000Tokens() public {
        vm.deal(Owner, 100 ether);

        assertEq(
            scoutToken.totalSupply(),
            initial_supply * (10 ** scoutToken.decimals()),
            "Different amount of minted token than expected!"
        );
    }
}
