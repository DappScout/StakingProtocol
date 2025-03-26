// SPDX-License-Identifier
pragma solidity ^0.8.28;

import {Script} from "lib/forge-std/src/Script.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {ScoutToken} from "../src/TokenERC20.sol";

contract DeployTokenERC20 is Script {
    function runTokenERC20(uint256 _initialSupply) external returns (ScoutToken) {
        vm.broadcast();
        ScoutToken scoutToken = new ScoutToken(_initialSupply);
        return scoutToken;
    }
}

contract DeployStakingContract is Script {
    function runStakingProtocol(address _initialOwner) external returns (StakingContract) {
        vm.broadcast();
        StakingContract stakingContract = new StakingContract(_initialOwner);
        return stakingContract;
    }
}
