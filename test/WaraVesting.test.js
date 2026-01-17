const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WaraVesting", function () {
    let WaraVesting, vesting;
    let WaraToken, token; // We will use a Mock mock or the real token logic
    let owner, addr1, addr2;

    const TOTAL_TEAM_RESERVE = ethers.parseEther("90000000"); // 90M

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // 1. Deploy Vesting First (owner is beneficiary)
        const VestingFactory = await ethers.getContractFactory("WaraVesting");
        vesting = await VestingFactory.deploy(owner.address);

        // 2. Deploy Token
        // Token Constructor: (dao, vesting, airdrop)
        // We use dummy addresses for dao/airdrop
        const TokenFactory = await ethers.getContractFactory("WaraToken");
        token = await TokenFactory.deploy(addr1.address, vesting.target || vesting.address, addr2.address);

        // 3. Link Token to Vesting
        await vesting.setToken(token.target || token.address);
    });

    it("Should hold 90M tokens initially", async function () {
        const balance = await token.balanceOf(vesting.target || vesting.address);
        expect(balance).to.equal(TOTAL_TEAM_RESERVE);
    });

    it("Should allow roughly 0 claim immediately after deployment", async function () {
        // Time 0 (might be +1 or +2 seconds due to deployment txs)
        const available = await vesting.getAvailableAmount();
        // Allow up to 20 WARA to be released in the first few seconds
        expect(available).to.be.closeTo(0, ethers.parseEther("20"));

        // Only fails if amount > 0, but since we have >0 now, claim shouldn't fail if amount >0
        // We just check that we can claim 'available'
        if (available > 0n) {
            await vesting.claim(); // Should succeed
        } else {
            await expect(vesting.claim()).to.be.revertedWith("No tokens available for claim yet");
        }
    });

    it("Should release 50% of tokens after 6 months", async function () {
        const halfYear = 182.5 * 24 * 60 * 60; // ~6 months in seconds

        // Increase time
        await ethers.provider.send("evm_increaseTime", [Math.floor(halfYear)]);
        await ethers.provider.send("evm_mine");

        const available = await vesting.getAvailableAmount();

        // Check roughly 50%
        const expected = TOTAL_TEAM_RESERVE / 2n;
        // Increase delta to 5000 WARA to be safe with block times
        const delta = ethers.parseEther("5000");

        expect(available).to.be.closeTo(expected, delta);

        // Claim
        const ownerBalanceBefore = await token.balanceOf(owner.address);
        await vesting.claim();
        const ownerBalanceAfter = await token.balanceOf(owner.address);

        // Since claim() executes in a new block (time progresses), amount might be slightly higher than 'available' view
        expect(ownerBalanceAfter - ownerBalanceBefore).to.be.closeTo(available, ethers.parseEther("100"));
    });

    it("Should release 100% after 1 year", async function () {
        const fullYear = 365 * 24 * 60 * 60 + 100; // 1 year + buffer

        await ethers.provider.send("evm_increaseTime", [fullYear]);
        await ethers.provider.send("evm_mine");

        const available = await vesting.getAvailableAmount();
        expect(available).to.equal(TOTAL_TEAM_RESERVE);

        await vesting.claim();

        const vestingBalance = await token.balanceOf(vesting.target || vesting.address);
        expect(vestingBalance).to.equal(0);
    });

    it("Should prevent non-owners from setting token or claiming", async function () {
        await expect(
            vesting.connect(addr1).claim()
        ).to.be.reverted;// Ownable error message depends on version

        // Try to reset token
        await expect(
            vesting.connect(addr1).setToken(addr2.address)
        ).to.be.reverted;
    });
});
