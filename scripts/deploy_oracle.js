const hre = require("hardhat");

async function main() {
    const NODE_REGISTRY_ADDRESS = "0x4dEfD40BAF4c290F8bc9F947cBc82865f4cE49e4";
    const INITIAL_PRICE = hre.ethers.parseUnits("0.75", 8); // $0.75 USD inicial

    const [deployer] = await hre.ethers.getSigners();
    console.log("🚀 Deploying WaraOracle with account:", deployer.address);

    const WaraOracle = await hre.ethers.getContractFactory("WaraOracle");
    const oracle = await WaraOracle.deploy(NODE_REGISTRY_ADDRESS, INITIAL_PRICE);

    await oracle.waitForDeployment();
    const oracleAddress = await oracle.getAddress();

    console.log("=========================================");
    console.log("✅ WaraOracle deployed to:", oracleAddress);
    console.log("Copy this address to Wara/src/contracts.ts");
    console.log("=========================================");

    // Opción: Transferir propiedad a una DAO o mantenerla para ajustes de Quorum
    console.log("Current Quorum: 50% of active nodes.");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
