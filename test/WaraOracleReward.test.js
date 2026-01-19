const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Wara Oracle - Dynamic Rewards Suite", function () {
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

        // 0.5 WARA initial -> 0.2 WARA floor
        await oracle.setParams(
            20,
            ethers.parseUnits("0.5", 18),
            ethers.parseUnits("0.2", 18),
            await gasPool.getAddress(),
            await linkRegistry.getAddress()
        );
    });

    it("Dynamic Reward: Should be 0.5 WARA when few nodes exist", async function () {
        const reward = await oracle.getDynamicReward(1);
        expect(reward).to.equal(ethers.parseUnits("0.5", 18));
    });

    it("Dynamic Reward: Should decrease as network grows", async function () {
        // At 105 nodes: 
        // 105 - 5 = 100 nodes extra.
        // 100 * 0.001 = 0.1 WARA deduction.
        // 0.5 - 0.1 = 0.4 WARA.
        const reward = await oracle.getDynamicReward(105);
        expect(reward).to.equal(ethers.parseUnits("0.4", 18));
    });

    it("Dynamic Reward: Should hit the floor of 0.2 WARA", async function () {
        // At 1000 nodes:
        // (1000 - 5) * 0.001 = 0.995 WARA deduction.
        // 0.5 - 0.995 is negative, so should return floor (0.2).
        const reward = await oracle.getDynamicReward(1000);
        expect(reward).to.equal(ethers.parseUnits("0.2", 18));
    });
});
