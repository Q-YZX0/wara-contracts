const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Adding Liquidity with account:", deployer.address);

    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("Current ETH Balance:", hre.ethers.formatEther(balance));

    // CONSTANTS
    const WARA_ADDRESS = "0x77815D33563D53e33eF7939765c85b8F4169A660"; // Deployed Logic
    // Sepolia Uniswap V2 Router (Standard)
    const ROUTER_ADDRESS_RAW = "0xc532a742dff9ea40e195070f7093896d472f9713";
    const ROUTER_ADDRESS = hre.ethers.getAddress(ROUTER_ADDRESS_RAW);

    // AMOUNTS
    // 200,000,000 WARA (Liquidity Allocation)
    const TOKEN_AMOUNT = hre.ethers.parseUnits("200000000", 18);
    // 1 ETH
    const ETH_AMOUNT = hre.ethers.parseEther("1.0");

    // 1. Connect to Token
    const WaraToken = await hre.ethers.getContractAt("WaraToken", WARA_ADDRESS, deployer);

    // Check WARA Balance
    const waraBal = await WaraToken.balanceOf(deployer.address);
    console.log(`WARA Balance: ${hre.ethers.formatUnits(waraBal, 18)}`);

    if (waraBal < TOKEN_AMOUNT) {
        console.error("Insufficient WARA balance for liquidity!");
        return;
    }

    // 2. Approve Router
    console.log(`\nApproving Uniswap Router to spend ${hre.ethers.formatUnits(TOKEN_AMOUNT, 18)} WARA...`);
    const txApprove = await WaraToken.approve(ROUTER_ADDRESS, TOKEN_AMOUNT);
    await txApprove.wait();
    console.log("Approval Confirmed.");

    // 3. Add Liquidity
    console.log("\nAdding Liquidity (WARA + ETH)...");

    // Minimal Interface for Router
    const routerAbi = [
        "function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity)"
    ];
    const router = new hre.ethers.Contract(ROUTER_ADDRESS, routerAbi, deployer);

    // Deadline = 10 mins from now
    const deadline = Math.floor(Date.now() / 1000) + 600;

    const txAdd = await router.addLiquidityETH(
        WARA_ADDRESS,
        TOKEN_AMOUNT,
        0, // Slippage 100% allowed for initial seeding (accept any amount of tokens)
        0, // Slippage 100% (accept any amount of ETH)
        deployer.address, // LP tokens go to deployer (Provider of Liquidity)
        deadline,
        { value: ETH_AMOUNT }
    );

    console.log(`Transaction sent: ${txAdd.hash}`);
    await txAdd.wait();

    console.log("\n✅ Liquidity Added Successfully!");
    console.log("Pair created/updated on Uniswap V2 Sepolia.");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
