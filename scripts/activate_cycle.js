const hre = require("hardhat");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

/**
 * WaraAirdrop Cycle Activator
 * 1. Fetches registered users from the contract
 * 2. Rewards top participants or random lucky users
 * 3. Generates Merkle Tree and Root
 * 4. Pushes Root to the WaraAirdrop contract as Owner
 * 5. Saves the Proofs for the frontend
 */
async function main() {
    const AIRDROP_ADDRESS = "0x..."; // SUSTITUIR POR LA DIRECCIÓN REAL AL DESPLEGAR
    const WaraAirdrop = await hre.ethers.getContractAt("WaraAirdrop", AIRDROP_ADDRESS);

    console.log("📡 Fetching registered users...");
    const users = await WaraAirdrop.getRegisteredUsers();

    if (users.length === 0) {
        console.log("❌ No registered users. Airdrop cycle aborted.");
        return;
    }

    console.log(`✅ Found ${users.length} registered users.`);

    // 💡 ESTRATEGIA: Seleccionamos a todos o a un subconjunto aleatorio
    // Para simplificar, premiaremos a TODOS con 100 WARA este ciclo.
    const rewardAmount = hre.ethers.parseEther("100");

    // 1. Crear hojas para el Merkle Tree
    // Las hojas deben ser: hash(address + amount)
    const elements = users.map(addr => {
        return Buffer.from(
            hre.ethers.solidityPackedKeccak256(["address", "uint256"], [addr, rewardAmount]).slice(2),
            "hex"
        );
    });

    // 2. Generar Merkle Tree
    const merkleTree = new MerkleTree(elements, keccak256, { sortPairs: true });
    const root = merkleTree.getHexRoot();

    console.log("🌿 Merkle Root Generated:", root);

    // 3. Subir el Root al contrato (Requiere Owner Wallet)
    console.log("⏳ Sending transaction to WaraAirdrop contract...");
    try {
        const tx = await WaraAirdrop.startNewCycle(root);
        await tx.wait();
        console.log(`🚀 Cycle Started! Transaction: ${tx.hash}`);
    } catch (error) {
        console.error("❌ Failed to start cycle. Is the 30-day cooldown over?", error.message);
        return;
    }

    // 4. Guardar las pruebas (Proofs) para que el Frontend de Muggi las use
    const claims = {};
    users.forEach((addr, index) => {
        claims[addr] = {
            amount: rewardAmount.toString(),
            proof: merkleTree.getHexProof(elements[index])
        };
    });

    const fs = require("fs");
    const path = require("path");

    // Guardar en la carpeta de datos del nodo para que el backend lo encuentre
    const airdropDir = path.join(process.cwd(), "..", "wara_store", "airdrops");
    if (!fs.existsSync(airdropDir)) fs.mkdirSync(airdropDir, { recursive: true });

    const fileName = `cycle_${root.slice(0, 10)}.json`;
    const filePath = path.join(airdropDir, fileName);

    fs.writeFileSync(filePath, JSON.stringify({ cycleId: 1, root, claims }, null, 2));

    console.log(`📁 Airdrop claim data saved to: ${filePath}`);
    console.log("Distribute this file to your Frontend/Server so users can claim their tokens!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
