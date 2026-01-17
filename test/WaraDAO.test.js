const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WaraDAO", function () {
    let WaraDAO, dao;
    let WaraToken, token; // Mock or real token
    let owner, vesting, airdrop, voter1, voter2, recipient;

    beforeEach(async function () {
        [owner, vesting, airdrop, voter1, voter2, recipient] = await ethers.getSigners();

        // 1. Deploy DAO first
        const DAOFactory = await ethers.getContractFactory("WaraDAO");
        dao = await DAOFactory.deploy();

        // 2. Deploy Token passing pure actors for initial allocation
        // Constructor: (dao, vesting, airdrop)
        // vesting gets 90M, airdrop gets 70M
        const TokenFactory = await ethers.getContractFactory("WaraToken");
        token = await TokenFactory.deploy(dao.target || dao.address, vesting.address, airdrop.address);

        // 3. Link Token to DAO
        await dao.setToken(token.target || token.address);

        // 4. Distribute tokens to CLEAN voters (voter1, voter2) from owner (who has 310M)
        await token.transfer(voter1.address, ethers.parseEther("100")); // Voter 1: 100 tokens
        await token.transfer(voter2.address, ethers.parseEther("50"));  // Voter 2: 50 tokens

        // Delegate votes if Token uses ERC20Votes checks (WaraDAO uses simple balanceOf, so this is optional but good practice)
        await token.connect(voter1).delegate(voter1.address);
        await token.connect(voter2).delegate(voter2.address);
    });

    it("Should create a proposal correctly", async function () {
        await dao.createProposal("Test Proposal", recipient.address, ethers.parseEther("10"), 0); // 0 = GENERAL

        const proposal = await dao.proposals(0);
        expect(proposal.description).to.equal("Test Proposal");
        expect(proposal.recipient).to.equal(recipient.address);
        expect(proposal.amount).to.equal(ethers.parseEther("10"));
        expect(proposal.pType).to.equal(0);
        expect(proposal.executed).to.equal(false);
    });

    it("Should cast votes weighted by token balance", async function () {
        await dao.createProposal("Test Proposal", recipient.address, ethers.parseEther("10"), 0);

        // Voter1 votes YES (Side 1)
        await dao.connect(voter1).vote(0, 1);

        const proposalAfterVote1 = await dao.proposals(0);
        expect(proposalAfterVote1.upvotes).to.equal(ethers.parseEther("100"));

        // Voter2 votes NO (Side 0)
        await dao.connect(voter2).vote(0, 0);

        const proposalAfterVote2 = await dao.proposals(0);
        expect(proposalAfterVote2.downvotes).to.equal(ethers.parseEther("50"));
    });

    it("Should prevent double voting", async function () {
        await dao.createProposal("Test Proposal", recipient.address, 100, 0);
        await dao.connect(voter1).vote(0, 1);

        await expect(
            dao.connect(voter1).vote(0, 1)
        ).to.be.revertedWith("Already voted");
    });

    it("Should execute a passed proposal and transfer funds", async function () {
        const amount = ethers.parseEther("10");
        await dao.createProposal("Funding Proposal", recipient.address, amount, 0);

        // Voter1 (100 tokens) votes YES
        await dao.connect(voter1).vote(0, 1);

        // Voter2 (50 tokens) votes NO
        await dao.connect(voter2).vote(0, 0);

        // Increase time to pass deadline (3 days)
        await ethers.provider.send("evm_increaseTime", [3 * 24 * 60 * 60 + 1]);
        await ethers.provider.send("evm_mine");

        // Execute
        const recipientBalanceBefore = await token.balanceOf(recipient.address);
        await dao.executeProposal(0);
        const recipientBalanceAfter = await token.balanceOf(recipient.address);

        const proposal = await dao.proposals(0);
        expect(proposal.executed).to.be.true;
        expect(proposal.approved).to.be.true;

        // Check transfer
        expect(recipientBalanceAfter - recipientBalanceBefore).to.equal(amount);
    });

    it("Should fail execution if deadline not reached", async function () {
        await dao.createProposal("Early Exec", recipient.address, 100, 0);
        await expect(dao.executeProposal(0)).to.be.revertedWith("Deadline not reached");
    });
});
