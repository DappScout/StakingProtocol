// SPDX-License-identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ScoutToken} from "./TokenERC20.sol";

contract StakingContract is Ownable(msg.sender), Pausable {
uint256 test;

constructor(address initialOwner){}



}
