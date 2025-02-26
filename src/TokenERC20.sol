// SPDX-License-identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ScoutToken
/// @author DappScout
/// @notice Implementation of an ERC20 token for ScoutStakingProtocol
/// @dev Using OpenZeppelin's ERC20 implementation

contract ScoutToken is ERC20{
 
 constructor() ERC20("ScoutToken", "SCT"){
    _mint(msg.sender, 10000);
 }






}