// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ScoutToken contract
/// @author DappScout
/// @notice Implementation of an ERC20 token for ScoutStakingProtocol
/// @dev Using OpenZeppelin's ERC20 implementation

contract ScoutToken is ERC20, Ownable(msg.sender) {
    constructor(uint256 _initialSupply) ERC20("ScoutToken", "SCT") {
        _mint(msg.sender, _initialSupply * (10 ** decimals()));
    }

    function mint(address _user, uint256 _amount) public onlyOwner {
        _mint(_user, _amount);
    }
}
