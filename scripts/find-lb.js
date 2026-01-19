const hre = require("hardhat");
async function main() {
    const linkRegistryAddress = "0x8E5c574e89ac6A8FbD7D3EB5584c628C5E7f4bCC";
    const lr = await hre.ethers.getContractAt("LinkRegistry", linkRegistryAddress);
    const lbAddress = await lr.LeaderBoardContract();
    console.log("LeaderBoard Address:", lbAddress);
}
main().catch(console.error);
