const hre = require("hardhat");

/**
 * Funding Utility
 * Sends ETH and WARA to a specific address.
 */
async function main() {
    // ADJUST THESE VALUES
    const RECIPIENT = "0x5D856AB977D8dE98408A5Bcc0fFE15A17Af0c6F2";
    const TOKEN_ADDRESS = ""; // Add WaraToken address here
    const ETH_AMOUNT = "0.1";
    const WARA_AMOUNT = "1000";

    const [sender] = await hre.ethers.getSigners();
    console.log(`🏦 [FUNDING] From ${sender.address} to ${RECIPIENT}...`);

    // 1. Send ETH
    console.log(`🔹 Sending ${ETH_AMOUNT} ETH...`);
    const txEth = await sender.sendTransaction({
        to: RECIPIENT,
        value: hre.ethers.parseEther(ETH_AMOUNT)
    });
    await txEth.wait();
    console.log(`✅ ETH Sent! Hash: ${txEth.hash}`);

    // 2. Send WARA (if address provided)
    if (TOKEN_ADDRESS && TOKEN_ADDRESS !== "") {
        console.log(`🔹 Sending ${WARA_AMOUNT} WARA...`);
        const token = await hre.ethers.getContractAt("WaraToken", TOKEN_ADDRESS);
        const txWara = await token.transfer(RECIPIENT, hre.ethers.parseEther(WARA_AMOUNT));
        await txWara.wait();
        console.log(`✅ WARA Sent! Hash: ${txWara.hash}`);
    } else {
        console.log("⚠️ TOKEN_ADDRESS not set, skipping WARA transfer.");
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
