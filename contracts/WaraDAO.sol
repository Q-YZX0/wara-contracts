// SPDX-License-Identifier: MIT
// Wara Network - WaraDAO
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WaraDAO
 * @dev Governance contract to manage 35% of WARA supply (DAO + Marketing/Public Awareness).
 * Allows creating proposals to release funds for specific purposes.
 */
interface IVotes {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);
}

contract WaraDAO is Ownable {
    
    IERC20 public waraToken;
    
    enum ProposalType { GENERAL, MARKETING }
    
    struct Proposal {
        uint256 id;
        string description;
        address recipient;
        uint256 amount;
        ProposalType pType;
        uint256 upvotes;
        uint256 downvotes;
        uint256 deadline;
        uint256 snapshotBlock; // Flash Loan Protection
        bool executed;
        bool approved;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public nextProposalId;
    
    // Voter tracking to prevent double voting per proposal
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    uint256 public constant QUORUM_PERCENT = 5; // 5% of voters needed? (Simple logic for now)
    uint256 public constant VOTING_PERIOD = 3 days;

    event ProposalCreated(uint256 indexed id, string description, address recipient, uint256 amount, ProposalType pType);
    event Voted(uint256 indexed id, address voter, int8 side, uint256 weight);
    event ProposalExecuted(uint256 indexed id, bool approved);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Link the token after deployment
     */
    function setToken(address _token) external onlyOwner {
        waraToken = IERC20(_token);
    }

    /**
     * @notice Create a proposal to spend funds from the DAO Treasury or Marketing budget
     */
    function createProposal(
        string calldata description,
        address recipient,
        uint256 amount,
        ProposalType pType
    ) external returns (uint256) {
        // Option: Require proposer to have certain amount of tokens?
        
        uint256 pId = nextProposalId++;
        Proposal storage p = proposals[pId];
        p.id = pId;
        p.description = description;
        p.recipient = recipient;
        p.amount = amount;
        p.pType = pType;
        p.deadline = block.timestamp + VOTING_PERIOD;
        p.snapshotBlock = block.number;
        
        emit ProposalCreated(pId, description, recipient, amount, pType);
        return pId;
    }

    /**
     * @notice Vote on a proposal using WARA token balance as weight
     */
    function vote(uint256 pId, int8 side) external {
        Proposal storage p = proposals[pId];
        require(block.timestamp < p.deadline, "Voting period ended");
        require(!hasVoted[pId][msg.sender], "Already voted");
        
        // Use historical voting power to prevent Flash Loan attacks
        uint256 weight = IVotes(address(waraToken)).getPastVotes(msg.sender, p.snapshotBlock);
        require(weight > 0, "No voting power (must hold WARA at snapshot)");

        if (side > 0) {
            p.upvotes += weight;
        } else {
            p.downvotes += weight;
        }

        hasVoted[pId][msg.sender] = true;
        emit Voted(pId, msg.sender, side, weight);
    }

    /**
     * @notice Executes the proposal if it passed and deadline is reached
     */
    function executeProposal(uint256 pId) external {
        Proposal storage p = proposals[pId];
        require(block.timestamp >= p.deadline, "Deadline not reached");
        require(!p.executed, "Already executed");

        p.executed = true;
        
        // Check Quorum
        uint256 totalVotes = p.upvotes + p.downvotes;
        uint256 totalSupplySnapshot = IVotes(address(waraToken)).getPastTotalSupply(p.snapshotBlock);
        uint256 minQuorum = (totalSupplySnapshot * QUORUM_PERCENT) / 100;

        require(totalVotes >= minQuorum, "Quorum not reached");

        // Simple Passing Logic: More upvotes than downvotes
        if (p.upvotes > p.downvotes) {
            p.approved = true;
            require(waraToken.transfer(p.recipient, p.amount), "Transfer failed");
        }

        emit ProposalExecuted(pId, p.approved);
    }

    /**
     * @dev Fallback to receive ETH if needed (optional)
     */
    receive() external payable {}
}
