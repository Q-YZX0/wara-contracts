const hre = require("hardhat");

/**
 * Full Deployment Script for Wara Ecosystem
 * Works on Local Hardhat Network and Sepolia.
 */
async function main() {
    const network = await hre.network.name;
    console.log(`🚀 Starting Full Wara Ecosystem Deployment on [${network}]...`);

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deployer:", deployer.address);
    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("Balance:", hre.ethers.formatEther(balance), "ETH");

    // 1. Core Structures
    // WaraVesting (9% Team)
    console.log("\n1a. Deploying WaraVesting...");
    const WaraVesting = await hre.ethers.getContractFactory("WaraVesting");
    const vesting = await WaraVesting.deploy(deployer.address);
    await vesting.waitForDeployment();
    const vestingAddress = await vesting.getAddress();
    console.log(`WaraVesting: ${vestingAddress}`);

    // WaraDAO (35% Community)
    console.log("\n1b. Deploying WaraDAO...");
    const WaraDAO = await hre.ethers.getContractFactory("WaraDAO");
    // We pass Token later or now? Token needs DAO address for minting.
    // DAO needs Token address for Governance.
    // Circular Dependency Solution: Deploy DAO -> Deploy Token(DAO) -> DAO.setToken(Token)
    const dao = await WaraDAO.deploy(); // No args in constructor
    await dao.waitForDeployment();
    const daoAddress = await dao.getAddress();
    console.log(`WaraDAO: ${daoAddress}`);

    // WaraAirdrop (Community Rewards) - Moved up for Token Constructor
    console.log("\n1c. Deploying WaraAirdrop...");
    const WaraAirdrop = await hre.ethers.getContractFactory("WaraAirdrop");
    // Pass ZeroAddress initially, will setToken later
    const airdrop = await WaraAirdrop.deploy();
    await airdrop.waitForDeployment();
    const airdropAddress = await airdrop.getAddress();
    console.log(`WaraAirdrop: ${airdropAddress}`);

    // WaraToken (WARA)
    console.log("\n1d. Deploying WaraToken...");
    const WaraToken = await hre.ethers.getContractFactory("WaraToken");
    // Constructor: (address _dao, address _vesting, address _airdrop)
    const token = await WaraToken.deploy(daoAddress, vestingAddress, airdropAddress);
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log(`WaraToken: ${tokenAddress}`);

    // Set Token in DAO and Airdrop
    console.log("-> Wiring Token to DAO & Airdrop...");
    await dao.setToken(tokenAddress);
    // await airdrop.setToken(tokenAddress); // Will need to ensure this method exists

    // Set Token in DAO
    console.log("-> Wiring Token to DAO...");
    await dao.setToken(tokenAddress);

    // 2. Price Feeds
    let ethFeedAddress;
    let waraFeedAddress;

    // --- ETH/USD Feed (For Node Registration) ---
    if (network === "sepolia") {
        ethFeedAddress = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // Real Sepolia Chainlink Feed
        console.log(`\n2a. Using Real ETH/USD Feed: ${ethFeedAddress}`);
    } else {
        console.log("\n2a. Deploying Mock ETH/USD Feed...");
        const MockV3Aggregator = await hre.ethers.getContractFactory("MockV3Aggregator");
        const ethMock = await MockV3Aggregator.deploy(8, 250000000000); // Fixed $2500 ETH
        await ethMock.waitForDeployment();
        ethFeedAddress = await ethMock.getAddress();
        console.log(`Mock ETH Feed: ${ethFeedAddress}`);
    }

    // --- WARA/USD Feed (For Ads & Subs - FIXED @ $0.75) ---
    console.log("\n2b. Deploying Internal WARA/USD Feed ($0.75)...");
    const MockV3Aggregator = await hre.ethers.getContractFactory("MockV3Aggregator");
    // $0.75 = 75,000,000 (8 decimals)
    const waraMock = await MockV3Aggregator.deploy(8, 75000000);
    await waraMock.waitForDeployment();
    waraFeedAddress = await waraMock.getAddress();
    console.log(`WARA Price Manager: ${waraFeedAddress}`);

    // 3. GasPool
    console.log("\n3. Deploying GasPool...");
    const GasPool = await hre.ethers.getContractFactory("GasPool");
    const gasPool = await GasPool.deploy();
    await gasPool.waitForDeployment();
    const gasPoolAddress = await gasPool.getAddress();
    console.log(`GasPool: ${gasPoolAddress}`);

    // 4. AdManager
    console.log("\n4. Deploying AdManager...");
    const AdManager = await hre.ethers.getContractFactory("AdManager");
    const adManager = await AdManager.deploy(tokenAddress, waraFeedAddress);
    await adManager.waitForDeployment();
    const adManagerAddress = await adManager.getAddress();
    console.log(`AdManager: ${adManagerAddress}`);

    // 5. Subscriptions
    console.log("\n5. Deploying Subscriptions...");
    const Subscriptions = await hre.ethers.getContractFactory("Subscriptions");
    const subscription = await Subscriptions.deploy(
        tokenAddress,
        waraFeedAddress,
        deployer.address, // Treasury
        deployer.address  // Creator
    );
    await subscription.waitForDeployment();
    const subAddress = await subscription.getAddress();
    console.log(`Subscriptions: ${subAddress}`);

    // 6. NodeRegistry
    console.log("\n6. Deploying NodeRegistry...");
    const NodeRegistry = await hre.ethers.getContractFactory("NodeRegistry");
    const nodeRegistry = await NodeRegistry.deploy();
    await nodeRegistry.waitForDeployment();
    const registryAddress = await nodeRegistry.getAddress();
    console.log(`NodeRegistry: ${registryAddress}`);

    // 7. LeaderBoard
    console.log("\n7. Deploying LeaderBoard...");
    const LeaderBoard = await hre.ethers.getContractFactory("LeaderBoard");
    const leaderBoard = await LeaderBoard.deploy(deployer.address);
    await leaderBoard.waitForDeployment();
    const leaderBoardAddress = await leaderBoard.getAddress();
    console.log(`LeaderBoard: ${leaderBoardAddress}`);

    // 8. LinkRegistry
    console.log("\n8. Deploying LinkRegistry...");
    const LinkRegistry = await hre.ethers.getContractFactory("LinkRegistry");
    const linkRegistry = await LinkRegistry.deploy(leaderBoardAddress, tokenAddress, gasPoolAddress);
    await linkRegistry.waitForDeployment();
    const linkRegistryAddress = await linkRegistry.getAddress();
    console.log(`LinkRegistry: ${linkRegistryAddress}`);

    // 9. MediaRegistry (DAO Content)
    console.log("\n9. Deploying MediaRegistry...");
    const MediaRegistry = await hre.ethers.getContractFactory("MediaRegistry");
    const mediaRegistry = await MediaRegistry.deploy(tokenAddress);
    await mediaRegistry.waitForDeployment();
    const mediaRegistryAddress = await mediaRegistry.getAddress();
    console.log(`MediaRegistry: ${mediaRegistryAddress}`);

    // --- WIRING UP ---
    console.log("\n10. Wiring up contracts...");
    await adManager.setLinkReputation(linkRegistryAddress);
    await nodeRegistry.setGasPool(gasPoolAddress);
    await leaderBoard.setLinkRegistryContract(linkRegistryAddress);

    // Complete Circular Wiring
    console.log("-> Wiring Token to Airdrop...");
    await airdrop.setToken(tokenAddress);

    // Fund Airdrop (10% = 100,000,000 Tokens)
    // The tokens were minted to deployer in constructor (Optionally) or we transfer them now.
    // In WaraToken.sol: _mint(msg.sender, 260_000_000 * decimalsUnit) -> This is the Airdrop + Public + Liquidity part
    // Let's send the Airdrop share:
    console.log("-> Funding Airdrop (10%)...");
    const airdropAmount = hre.ethers.parseEther("100000000"); // 100M
    await token.transfer(airdropAddress, airdropAmount);

    // GasPool Approvals
    await gasPool.setManagerStatus(linkRegistryAddress, true);
    await gasPool.setManagerStatus(registryAddress, true); // Authorized for Sentinel Drips

    console.log("All connections established (including GasPool Drip System).");

    console.log("\n--- DEPLOYMENT COMPLETE ---");
    console.log(`WARA_TOKEN_ADDRESS="${tokenAddress}"`);
    console.log(`AD_MANAGER_ADDRESS="${adManagerAddress}"`);
    console.log(`SUBSCRIPTION_ADDRESS="${subAddress}"`);
    console.log(`NODE_REGISTRY_ADDRESS="${registryAddress}"`);
    console.log(`GAS_POOL_ADDRESS="${gasPoolAddress}"`);
    console.log(`LEADER_BOARD_ADDRESS="${leaderBoardAddress}"`);
    console.log(`LINK_REGISTRY_ADDRESS="${linkRegistryAddress}"`);
    console.log(`MEDIA_REGISTRY_ADDRESS="${mediaRegistryAddress}"`);
    console.log(`WARA_DAO_ADDRESS="${daoAddress}"`);
    console.log(`WARA_VESTING_ADDRESS="${vestingAddress}"`);
    console.log(`WARA_AIRDROP_ADDRESS="${airdropAddress}"`);
    console.log("---------------------------\n");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
