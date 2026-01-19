const hre = require("hardhat");
async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("Deployer Address:", deployer.address);
    console.log("Balance:", hre.ethers.formatEther(balance), "ETH");
}
main().catch(console.error);
