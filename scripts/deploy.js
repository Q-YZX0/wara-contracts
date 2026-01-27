const hre = require("hardhat");

/**
 * Full Clean Deployment Script - Wara Ecosystem (Industrial Edition)
 * Includes: Automated Uniswap Liquidity Injection
 */
async function main() {
    const network = await hre.network.name;
    const isLocal = network === "hardhat" || network === "localhost";

    console.log(`🚀 DEPLOYING NEW WARA ARCHITECTURE ON [${network}]...`);

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deployer:", deployer.address);

    const UNISWAP_ROUTER = "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008"; // Sepolia

    // Minimal ABIs for liquidity injection
    const IERC20_ABI = [
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function balanceOf(address account) external view returns (uint256)"
    ];
    const ROUTER_ABI = [
        "function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity)"
    ];

    // --- EXISTING ADDRESSES (from contracts.ts) ---
    // Only registry and oracle are empty = will be deployed
    const addresses = {
        vesting: "",
        dao: "",
        airdrop: "",
        registry: "", // WILL BE DEPLOYED
        gasPool: "",
        linkRegistry: "",
        subscriptions: "",
        token: "",
        oracle: "", // WILL BE DEPLOYED
        adManager: "",
        mediaRegistry: ""
    };

    // 1. Framework Infrastructure
    console.log("\n--- 1. Infrastructure Layer ---");

    if (!addresses.vesting) {
        const WaraVesting = await hre.ethers.getContractFactory("WaraVesting");
        const vesting = await WaraVesting.deploy(deployer.address);
        await vesting.waitForDeployment();
        addresses.vesting = await vesting.getAddress();
        console.log(`Vesting: ${addresses.vesting}`);
    } else {
        console.log(`Vesting: ${addresses.vesting} (existing)`);
    }

    if (!addresses.dao) {
        const WaraDAO = await hre.ethers.getContractFactory("WaraDAO");
        const dao = await WaraDAO.deploy();
        await dao.waitForDeployment();
        addresses.dao = await dao.getAddress();
        console.log(`DAO: ${addresses.dao}`);
    } else {
        console.log(`DAO: ${addresses.dao} (existing)`);
    }

    if (!addresses.airdrop) {
        const WaraAirdrop = await hre.ethers.getContractFactory("WaraAirdrop");
        const airdrop = await WaraAirdrop.deploy();
        await airdrop.waitForDeployment();
        addresses.airdrop = await airdrop.getAddress();
        console.log(`Airdrop: ${addresses.airdrop}`);
    } else {
        console.log(`Airdrop: ${addresses.airdrop} (existing)`);
    }

    if (!addresses.registry) {
        const NodeRegistry = await hre.ethers.getContractFactory("NodeRegistry");
        const registry = await NodeRegistry.deploy();
        await registry.waitForDeployment();
        addresses.registry = await registry.getAddress();
        console.log(`Registry: ${addresses.registry} ✨ NEW`);
    } else {
        console.log(`Registry: ${addresses.registry} (existing)`);
    }

    if (!addresses.gasPool) {
        const GasPool = await hre.ethers.getContractFactory("GasPool");
        const gasPool = await GasPool.deploy();
        await gasPool.waitForDeployment();
        addresses.gasPool = await gasPool.getAddress();
        console.log(`GasPool: ${addresses.gasPool}`);
    } else {
        console.log(`GasPool: ${addresses.gasPool} (existing)`);
    }

    // 2. Specialized Pools (Need to exist for the Token to mint to them)
    console.log("\n--- 2. Specialized Reward Pools ---");

    // Leaderboard needed for LinkRegistry
    let lbAddress;
    if (!addresses.linkRegistry) {
        const LeaderBoard = await hre.ethers.getContractFactory("LeaderBoard");
        const lb = await LeaderBoard.deploy(deployer.address);
        await lb.waitForDeployment();
        lbAddress = await lb.getAddress();

        const LinkRegistry = await hre.ethers.getContractFactory("LinkRegistry");
        const lr = await LinkRegistry.deploy(lbAddress, hre.ethers.ZeroAddress, addresses.gasPool);
        await lr.waitForDeployment();
        addresses.linkRegistry = await lr.getAddress();
        console.log(`LinkRegistry (Reputation Pool): ${addresses.linkRegistry}`);
    } else {
        console.log(`LinkRegistry (Reputation Pool): ${addresses.linkRegistry} (existing)`);
    }

    if (!addresses.subscriptions) {
        const Subscriptions = await hre.ethers.getContractFactory("Subscriptions");
        const sub = await Subscriptions.deploy(hre.ethers.ZeroAddress, hre.ethers.ZeroAddress, deployer.address, deployer.address);
        await sub.waitForDeployment();
        addresses.subscriptions = await sub.getAddress();
        console.log(`Subscriptions (Hoster Pool): ${addresses.subscriptions}`);
    } else {
        console.log(`Subscriptions (Hoster Pool): ${addresses.subscriptions} (existing)`);
    }

    // 3. The Token (Sovereign Distribution)
    console.log("\n--- 3. WARA Token (The Big Bang) ---");
    if (!addresses.token) {
        const WaraToken = await hre.ethers.getContractFactory("WaraToken");
        const token = await WaraToken.deploy(
            addresses.dao,
            addresses.vesting,
            addresses.airdrop,
            addresses.subscriptions,
            addresses.linkRegistry
        );
        await token.waitForDeployment();
        addresses.token = await token.getAddress();
        console.log(`WARA Token: ${addresses.token}`);
    } else {
        console.log(`WARA Token: ${addresses.token} (existing)`);
    }

    if (!addresses.mediaRegistry) {
        const MediaRegistry = await hre.ethers.getContractFactory("MediaRegistry");
        const media = await MediaRegistry.deploy(addresses.token);
        await media.waitForDeployment();
        addresses.mediaRegistry = await media.getAddress();
        console.log(`MediaRegistry (Catalog): ${addresses.mediaRegistry}`);
    } else {
        console.log(`MediaRegistry (Catalog): ${addresses.mediaRegistry} (existing)`);
    }

    // --- LIQUIDITY INJECTION (Skip if token already existed) ---
    if ((network === "sepolia" || isLocal) && !addresses.token) {
        console.log("\n--- Injecting Uniswap Liquidity (2 ETH) ---");
        try {
            const waraAmount = hre.ethers.parseUnits("1000000", 18); // 1,000,000 WARA
            const ethAmount = hre.ethers.parseUnits("2", 18); // 2 ETH

            const tokenContract = new hre.ethers.Contract(addresses.token, IERC20_ABI, deployer);
            const router = new hre.ethers.Contract(UNISWAP_ROUTER, ROUTER_ABI, deployer);

            console.log(`Approving ${hre.ethers.formatUnits(waraAmount, 18)} WARA to Uniswap...`);
            await (await tokenContract.approve(UNISWAP_ROUTER, waraAmount)).wait();

            console.log(`Adding Liquidity: 2 ETH + 1,000,000 WARA...`);
            const tx = await router.addLiquidityETH(
                addresses.token,
                waraAmount,
                0, // slippage not critical for initial deploy
                0,
                deployer.address,
                Math.floor(Date.now() / 1000) + 600,
                { value: ethAmount }
            );
            await tx.wait();
            console.log("✅ Uniswap Pool Liquidity Provided!");
        } catch (e) {
            console.warn("⚠️ Uniswap Liquidity Step failed:", e.message);
        }
    }

    // 4. Final Wiring of Core (Only if contracts were just deployed)
    console.log("-> Initializing Module Connections...");
    if (!addresses.dao) {
        await (await hre.ethers.getContractAt("WaraDAO", addresses.dao)).setToken(addresses.token);
    }
    if (!addresses.subscriptions) {
        await (await hre.ethers.getContractAt("Subscriptions", addresses.subscriptions)).setWaraToken(addresses.token);
    }
    if (!addresses.linkRegistry) {
        await (await hre.ethers.getContractAt("LinkRegistry", addresses.linkRegistry)).setRewardToken(addresses.token);
    }
    if (!addresses.registry) {
        await (await hre.ethers.getContractAt("NodeRegistry", addresses.registry)).setGasPool(addresses.gasPool);
    }


    // 5. Oracle (Judge & Jury) - ALWAYS DEPLOY IF EMPTY
    console.log("\n--- 4. Decentralized Oracle System ---");
    if (!addresses.oracle) {
        const WaraOracle = await hre.ethers.getContractFactory("WaraOracle");
        const oracle = await WaraOracle.deploy(addresses.registry, 75000000); // Start at $0.75
        await oracle.waitForDeployment();
        addresses.oracle = await oracle.getAddress();
        console.log(`WaraOracle: ${addresses.oracle} ✨ NEW (Smart Committee)`);

        // Link Oracle to Infrastructure
        console.log("-> Authorizing Oracle for Rewards & Gas...");
        await (await hre.ethers.getContractAt("GasPool", addresses.gasPool)).setManagerStatus(addresses.oracle, true);
        await (await hre.ethers.getContractAt("LinkRegistry", addresses.linkRegistry)).setAuthorizedOracle(addresses.oracle);

        // Connect Subscriptions to Oracle
        console.log("-> Connecting Subscriptions to Price Oracle...");
        await (await hre.ethers.getContractAt("Subscriptions", addresses.subscriptions)).setPriceFeed(addresses.oracle);

        await (await hre.ethers.getContractAt("WaraOracle", addresses.oracle)).setParams(
            20,
            hre.ethers.parseUnits("0.5", 18),
            hre.ethers.parseUnits("0.2", 18),
            addresses.gasPool,
            addresses.linkRegistry
        );
    } else {
        console.log(`WaraOracle: ${addresses.oracle} (existing)`);
    }

    // 6. Economy Connectors
    console.log("\n--- 5. Economy Layer ---");
    if (!addresses.adManager) {
        const AdManager = await hre.ethers.getContractFactory("AdManager");
        const ad = await AdManager.deploy(addresses.token, addresses.oracle);
        await ad.waitForDeployment();
        addresses.adManager = await ad.getAddress();
        console.log(`AdManager: ${addresses.adManager}`);

        // Connect AdManager to LinkRegistry (Important for reward resolution)
        await (await hre.ethers.getContractAt("AdManager", addresses.adManager)).setLinkReputation(addresses.linkRegistry);
    } else {
        console.log(`AdManager: ${addresses.adManager} (existing)`);
        // Update oracle reference if oracle was just deployed
        if (!addresses.oracle) {
            console.log("-> Updating AdManager oracle reference...");
            await (await hre.ethers.getContractAt("AdManager", addresses.adManager)).setPriceFeed(addresses.oracle);
        }
    }

    console.log("\n=========================================");
    console.log("🏁 FULL ARCHITECTURE DEPLOYED SUCCESSFULLY");
    Object.keys(addresses).forEach(key => console.log(`${key.padEnd(14)}: ${addresses[key]}`));
    console.log("=========================================");
    console.log("ACTION: Update Wara/src/contracts.ts with these new addresses.");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
