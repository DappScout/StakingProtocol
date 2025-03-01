// SPDX-License-identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ScoutToken contract
/// @author DappScout
/// @notice Implementation of an ERC20 token for ScoutStakingProtocol
/// @dev Using OpenZeppelin's ERC20 implementation

contract ScoutToken is ERC20 {
    constructor(uint256 _initialSupply) ERC20("ScoutToken", "SCT") {
        _mint(msg.sender, _initialSupply * (10 ** decimals()));
    }
}
