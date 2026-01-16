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

    // 1. WaraToken (WARA)
    console.log("\n1. Deploying WaraToken...");
    const WaraToken = await hre.ethers.getContractFactory("WaraToken");
    const token = await WaraToken.deploy(hre.ethers.ZeroAddress, hre.ethers.ZeroAddress);
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log(`WaraToken: ${tokenAddress}`);

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
    console.log("---------------------------\n");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
