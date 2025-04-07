# Simple Staking Protocol 🎁

A secure ERC20 token staking protocol with dynamic reward calculation

## Overview 🔍

Simple Staking Protocol allows users to stake their ERC20 **Scout Tokens** and earn rewards over time. The protocol includes security measures like pausing capabilities, reentrancy protection, rate limiting, and owner-only administrative functions.

## Features 🧱

- **Staking & Unstaking**: Securely stake and unstake ERC20 tokens
- **Reward System**: Earn rewards at a rate of 0.1% per time unit
- **Dynamic Rewards**: Owner can adjust reward rates
- **Emergency Controls**: Contract can be paused by owner in case of emergencies
- **Security Measures**: Implements reentrancy guards, rate limiting, and other protections

## Architecture🌃

The protocol consists of the following components:

- `StakingContract.sol`: Core staking logic with security features
- `TokenERC20.sol`: ERC20 token implementation for staking

`TO DO: add mermaid diagram or graph---------------------------------------`

### Security Considerations🔒

This protocol implements multiple security features:
- OpenZeppelin's Pausable, ReentrancyGuard, and Ownable patterns
- SafeERC20 for secure token transfers
- Minimum staking amount requirements
- Rate limiting to prevent flash loan attacks
- Comprehensive event logging

## Getting Started🚀

### Prerequisites

- Solidity ^0.8.28
- Foundry (for testing and deployment)

### Libraries verisons
Built with 5.0.1 verison of OpenZeppelin's libraries

To install this version, you can run:
```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.0.1
```

### Installation

1. Clone the repository
```bash
git clone https://github.com/your-username/SimpleStakingProtocol.git
cd SimpleStakingProtocol
```

2. Install dependencies
```bash
forge install
```

### Deployment🚢

Use the provided deployment script:
```bash
forge script script/DeployProtocol.s.sol --rpc-url  --private-key 
```

### Testing🧪✅

Run the comprehensive test suite:
```bash
forge test
```

## Key Invariants🔐📏

The protocol maintains several critical invariants to ensure security and correctness:

- Total staked amount = Sum of all individual user stakes
- Contract token balance ≥ Total staked amount + unclaimed rewards
- User staked amount ≤ User token balance
- Only owner can pause/unpause contract and modify reward rates
- All state changes emit corresponding events


## License📄

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact✉️
![Simple Staking Protocol Banner](./assets/banner.png)

* [my Linktree](https://linktr.ee/DappScout)
* [my X](https://x.com/DappScout)

For questions or contributions, please open an issue on the repository. 

Thank u for checking out 🤠