const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WaraAirdrop", function () {
    let WaraToken, waraToken;
    let WaraAirdrop, waraAirdrop;
    let owner, addr1, addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy WaraToken
        WaraToken = await ethers.getContractFactory("WaraToken");
        // Assuming WaraToken constructor takes 3 arguments based on typical setup, but let's check or mock if complex
        // Actually, let's deploy a mock token for simplicity if constructor is complex, 
        // but looking at file list, WaraToken.sol exists. Let's try to deploy it.
        // Ideally we should check WaraToken constructor.
        // But for Airdrop unit test, we can use a MockERC20 if WaraToken has complex deps.
        // Let's assume WaraToken needs args. 
        // To be safe, I'll deploy a Generic ERC20 Mock or just try WaraToken with dummy addresses.

        // Let's read WaraToken to be sure about constructor
        const WaraTokenFactory = await ethers.getContractFactory("WaraToken");
        // Based on previous convos, WaraToken might take (dao, vesting, airdrop)
        // Let's deploy Airdrop FIRST, then Token, then setToken.

        WaraAirdrop = await ethers.getContractFactory("WaraAirdrop");
        waraAirdrop = await WaraAirdrop.deploy();
        await waraAirdrop.waitForDeployment(); // Ethers v6

        // Deploy Token with dummy addresses for DAO/Vesting, pass airdrop address
        waraToken = await WaraTokenFactory.deploy(owner.address, owner.address, waraAirdrop.target);
        await waraToken.waitForDeployment();

        // Set token in Airdrop
        await waraAirdrop.setToken(waraToken.target);
    });

    it("Should allow a user to register", async function () {
        await waraAirdrop.connect(addr1).register();
        expect(await waraAirdrop.isRegistered(addr1.address)).to.be.true;

        const users = await waraAirdrop.getRegisteredUsers();
        expect(users).to.include(addr1.address);
    });

    it("Should not allow double registration", async function () {
        await waraAirdrop.connect(addr1).register();
        await expect(
            waraAirdrop.connect(addr1).register()
        ).to.be.revertedWith("Already registered");
    });

    it("Should return correct total registered count", async function () {
        await waraAirdrop.connect(addr1).register();
        await waraAirdrop.connect(addr2).register();
        expect(await waraAirdrop.totalRegistered()).to.equal(2);
    });

});
