const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Wara Oracle - Full Security Suite", function () {
    let token, registry, gasPool, linkRegistry, oracle;
    let owner, judge, jury1, jury2, jury3, sybil;
    let initialPrice = 75000000; // $0.75

    before(async function () {
        [owner, judge, jury1, jury2, jury3, sybil] = await ethers.getSigners();

        const NodeRegistry = await ethers.getContractFactory("NodeRegistry");
        registry = await NodeRegistry.deploy();

        const GasPool = await ethers.getContractFactory("GasPool");
        gasPool = await GasPool.deploy();

        const LeaderBoard = await ethers.getContractFactory("LeaderBoard");
        const lb = await LeaderBoard.deploy(owner.address);

        const LinkRegistry = await ethers.getContractFactory("LinkRegistry");
        linkRegistry = await LinkRegistry.deploy(await lb.getAddress(), ethers.ZeroAddress, await gasPool.getAddress());

        const WaraOracle = await ethers.getContractFactory("WaraOracle");
        oracle = await WaraOracle.deploy(await registry.getAddress(), initialPrice);

        await gasPool.setManagerStatus(await oracle.getAddress(), true);
        await linkRegistry.setAuthorizedOracle(await oracle.getAddress());

        // 20% jury (Standard)
        await oracle.setParams(20, ethers.parseUnits("10", 18), await gasPool.getAddress(), await linkRegistry.getAddress());

        await owner.sendTransaction({ to: await gasPool.getAddress(), value: ethers.parseEther("1.0") });

        // Register 4 nodes
        const nodes = [
            { name: "judge_node", signer: judge, ip: "1.1.1.1" },
            { name: "jury_1", signer: jury1, ip: "2.2.2.2" },
            { name: "jury_2", signer: jury2, ip: "3.3.3.3" },
            { name: "sybil_node", signer: sybil, ip: "1.1.1.1" } // REPEAT IP as Judge
        ];

        for (const n of nodes) {
            await registry.connect(n.signer).registerNode(n.name, n.signer.address, { value: ethers.parseUnits("1", 15) });
            await registry.connect(n.signer).updateIP(n.ip);
        }
        await ethers.provider.send("evm_mine");
    });

    it("Anti-Sybil: Should reject if multiple signatures come from same IP (Judge + Sybil)", async function () {
        const newPrice = 80000000;
        const currentBlock = await ethers.provider.getBlock("latest");
        const timestamp = currentBlock.timestamp + 10;
        const chainId = (await ethers.provider.getNetwork()).chainId;

        const messageHash = ethers.solidityPackedKeccak256(["int256", "uint256", "uint256"], [newPrice, timestamp, chainId]);
        const sig1 = await judge.signMessage(ethers.getBytes(messageHash));
        const sigSybil = await sybil.signMessage(ethers.getBytes(messageHash));
        const sig2 = await jury1.signMessage(ethers.getBytes(messageHash));

        // Result: 3 signatures, but only 2 unique IPs (1.1.1.1 and 2.2.2.2). Minimum is 3.
        await expect(oracle.connect(judge).submitPrice(newPrice, timestamp, [sig1, sigSybil, sig2]))
            .to.be.revertedWith("Not enough unique jury signatures");
    });

    it("Consensus: Should accept update with 3 unique IPs and refund gas", async function () {
        const newPrice = 85000000;
        const currentBlock = await ethers.provider.getBlock("latest");
        const timestamp = currentBlock.timestamp + 20;
        const chainId = (await ethers.provider.getNetwork()).chainId;

        const messageHash = ethers.solidityPackedKeccak256(["int256", "uint256", "uint256"], [newPrice, timestamp, chainId]);
        const sig1 = await judge.signMessage(ethers.getBytes(messageHash));
        const sig2 = await jury1.signMessage(ethers.getBytes(messageHash));
        const sig3 = await jury2.signMessage(ethers.getBytes(messageHash));

        const balanceBefore = await ethers.provider.getBalance(judge.address);
        await oracle.connect(judge).submitPrice(newPrice, timestamp, [sig1, sig2, sig3]);
        const balanceAfter = await ethers.provider.getBalance(judge.address);

        expect(await oracle.latestAnswer()).to.equal(newPrice);
        const cost = balanceBefore - balanceAfter;
        console.log("Judge final cost after refund:", ethers.formatUnits(cost, "ether"), "ETH");
        expect(Number(ethers.formatUnits(cost, "ether"))).to.be.below(0.005);
    });
});
