const hre = require("hardhat");

/**
 * Seeding Script (DAO Proposals)
 * Proposes initial content to the MediaRegistry.
 */
async function main() {
    // ADJUST THIS VALUE
    const MEDIA_REGISTRY_ADDRESS = "";

    if (!MEDIA_REGISTRY_ADDRESS) {
        console.error("❌ MEDIA_REGISTRY_ADDRESS is required.");
        return;
    }

    const SEED_LIST = [
        { sourceId: "movie:550", title: "Fight Club" },
        { sourceId: "movie:27205", title: "Inception" },
        { sourceId: "movie:157336", title: "Interstellar" }
    ];

    const [signer] = await hre.ethers.getSigners();
    console.log(`🌱 [SEEDING] Proposing content as ${signer.address}...`);

    const registry = await hre.ethers.getContractAt("MediaRegistry", MEDIA_REGISTRY_ADDRESS);

    for (const item of SEED_LIST) {
        console.log(`🎬 Proposing: ${item.title} (${item.sourceId})...`);
        try {
            const tx = await registry.proposeMedia(item.sourceId, item.title, "custom", "{}");
            console.log(`⏳ TX: ${tx.hash}`);
            await tx.wait();
            console.log("✅ Proposed!");
        } catch (e) {
            console.log(`❌ Error: ${e.message}`);
        }
    }

    const total = await registry.getProposalCount();
    console.log(`\n📊 Total Proposals: ${total}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
