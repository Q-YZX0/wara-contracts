# Wara Smart Contracts

**Wara Smart Contracts** is the decentralized backbone of the Wara Network. It provides the source of truth for node discovery, a trustless economy for streaming, and a community-driven DAO for content management.

These contracts are deployed on the **Ethereum Sepolia** testnet.

---

## 🏛️ Ecosystem Architecture

The Wara smart contract suite is divided into three functional layers:

### 1. [The Discovery Layer](docs/discovery-layer.md)
Ensures that the Wara nodes can find each other and maintain their gas levels automatically.
-   **NodeRegistry**: The "Phonebook" of the network.
-   **GasPool**: The fuel management system (Sentinel auto-fills).

### 2. [The Economy Layer](docs/economy-layer.md)
Powers the USD-Stable streaming economy where hosters are rewarded in $WARA.
-   **WaraToken**: The native economy token.
-   **AdManager**: Handles ad campaigns and proof-of-view rewards.
-   **Subscriptions**: Manages premium access and reward pools.

### 3. [The Governance & Quality Layer](docs/governance-layer.md)
Powers the community-owned catalog and link verification system.
-   **MediaRegistry**: The official DAO-run content database.
-   **LinkRegistry**: Connects movies to streaming IPs via Trust Scores.
-   **LeaderBoard**: Tracks and ranks node performance.

---

## 🚀 Development & Deployment

### Essential Scripts
We use Hardhat for all blockchain operations.
-   `npm run deploy:sepolia`: Re-deploys the entire ecosystem and wires the contracts.
-   `npm run fund`: Utility to send ETH/WARA to a development wallet.
-   `npm run seed`: Populates the `MediaRegistry` with a test catalog for the DAO.

### Configuration
Update your `.env` file with the following:
-   `PRIVATE_KEY`: Your deployer wallet key.
-   `INFURA_API_KEY`: For network connectivity.
-   `RPC_URL`: Set to your Sepolia RPC provider.

---

## 🛡️ Security & Trust
Wara utilizes **Gasless Signatures (EIP-712)** for voting and ad rewards, ensuring that end-users never have to pay gas to interact with the protocol while maintaining full cryptographic security.

**License**: MIT. Developed by the Muggi/Wara Community.
