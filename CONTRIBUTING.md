# Contributing to Wara Contracts

Thank you for your interest in contributing to the Wara Network smart contracts! We are building the decentralized foundation for sovereign streaming.

## 🛠 Tech Stack
- **Language**: Solidity ^0.8.20
- **Framework**: Hardhat
- **Libraries**: OpenZeppelin (ERC20, Ownable, Permitted, Votes)
- **Decentralization**: Gasless Signatures (EIP-712), Community-governed Media Meta-Registry.

## 🚀 Getting Started

1.  **Clone the workspace**:
    ```bash
    git clone https://github.com/Q-YZX0/wara-contracts.git
    cd wara-contracts
    ```

2.  **Install dependencies**:
    ```bash
    npm install
    ```

3.  **Setup Environment**:
    Create a `.env` file based on the environment requirements:
    ```env
    PRIVATE_KEY=your_deployer_private_key
    INFURA_API_KEY=your_infura_key
    ```

## 🧪 Testing
We follow a strict testing policy for all core economic contracts.
```bash
npx hardhat test
```

## 📜 Development Guidelines

### 1. Solidity Style
- Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/v0.8.20/style-guide.html).
- Use `Sovereign Edition` patterns: all minted tokens must be allocated to automated pools (DAO, Vesting, Subscriptions, etc.) in the constructor of `WaraToken.sol`.

### 2. Gas Optimization
- Use `uint256` where possible instead of shorter types unless packing in storage.
- Avoid redundant state reads.
- Use `immutable` for addresses set at deployment.

### 3. Security
- Any changes to `recordPremiumViewBatch` or `batchClaimAdView` must be thoroughly audited for signature replay protection.
- Ensure all administrative functions are protected by `onlyOwner`.

## 📬 Pull Request Process
1.  Fork the repository and create your branch from `main`.
2.  If you've added code that should be tested, add tests.
3.  Ensure the test suite passes.
4.  Update the `README.md` or documentation if you've added new features or changed existing ones.
5.  Submit a Pull Request with a clear description of the changes.

## ⚖️ License
By contributing, you agree that your contributions will be licensed under the **MIT License**.

---
Developed by **YZX0**.
