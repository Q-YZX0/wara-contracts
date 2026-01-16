const hre = require("hardhat");

/**
 * Uniswap V2 Liquidity Pool Creation Script
 * This script adds 200,000,000 WARA to Uniswap V2 + ETH (Sepolia)
 */
async function main() {
    const WARA_TOKEN_ADDRESS = "0xc50Fc3c8110ed06f22f8567da1fA64bb1B2EB289";
    const UNISWAP_V2_ROUTER = "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008"; // Sepolia V2 Router

    const [deployer] = await hre.ethers.getSigners();
    console.log("🚀 Creating Liquidity Pool with account:", deployer.address);

    // 1. Get WARA Contract Instance
    const WaraToken = await hre.ethers.getContractAt("WaraToken", WARA_TOKEN_ADDRESS);

    // 2. Define Amounts
    // 200,000,000 WARA (as defined in tokenomics)
    const waraAmount = hre.ethers.parseEther("200000000");

    // 0.2 ETH as initial liquidity (adjust based on your Sepolia balance)
    const ethAmount = hre.ethers.parseEther("0.1");

    console.log(`📦 Preparing to add: ${hre.ethers.formatEther(waraAmount)} WARA and ${hre.ethers.formatEther(ethAmount)} ETH`);

    // 3. Approve Router to spend WARA
    console.log("⏳ Approving Uniswap Router...");
    const approveTx = await WaraToken.approve(UNISWAP_V2_ROUTER, waraAmount);
    await approveTx.wait();
    console.log("✅ Approved!");

    // 4. Add Liquidity
    // Using Uniswap V2 Router ABI snippet
    const routerAbi = [
        "function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity)"
    ];
    const router = new hre.ethers.Contract(UNISWAP_V2_ROUTER, routerAbi, deployer);

    console.log("⏳ Adding Liquidity to Uniswap V2...");

    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes from now

    const tx = await router.addLiquidityETH(
        WARA_TOKEN_ADDRESS,
        waraAmount,
        0, // amountTokenMin (slippage not an issue for initial pool)
        0, // amountETHMin
        deployer.address,
        deadline,
        { value: ethAmount }
    );

    console.log("⏳ Waiting for transaction confirmation...");
    const receipt = await tx.wait();

    console.log("=========================================");
    console.log("✅ Liquidity Pool Created Successfully!");
    console.log("Transaction Hash:", receipt.hash);
    console.log("Visit Uniswap to swap WARA now!");
    console.log("=========================================");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
