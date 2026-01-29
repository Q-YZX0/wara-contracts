// SPDX-License-Identifier: MIT
// Wara Network - MediaRegistry
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVotes {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);
}

/**
 * @title MediaRegistry
 * @notice Maestro de contenido con Gobernanza On-Chain.
 */
contract MediaRegistry is Ownable {

    struct MediaEntry {
        bytes32 id;             
        string source;          
        string externalId;      
        string title;           
        string metadataHash;    
        bool active;            
        uint256 createdAt;
    }

    struct Proposal {
        uint256 upvotes;
        uint256 downvotes;
        uint256 deadline;
        address proposer;
        uint256 snapshotBlock; // Flash Loan Protection
        bool executed;
    }

    IERC20 public waraToken;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant EXECUTION_REWARD = 50 * 10**18;
    uint256 public constant QUORUM_PERCENT = 1; // 1% Quorum for content

    mapping(bytes32 => MediaEntry) public mediaEntries;
    mapping(bytes32 => Proposal) public proposals;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;

    event MediaRegistered(bytes32 indexed id, string source, string externalId, string title);
    event ProposalCreated(bytes32 indexed id, string source, string externalId, string title, uint256 deadline);
    event Voted(bytes32 indexed id, address voter, int8 side);
    event ProposalExecuted(bytes32 indexed id, bool approved);

    constructor(address _tokenAddress) Ownable(msg.sender) {
        waraToken = IERC20(_tokenAddress);
    }

    function computeMediaId(string memory _source, string memory _externalId) public pure returns (bytes32) {
        return keccak256(abi.encode(_source, _externalId));
    }

    // --- OWNER DIRECT ---
    function registerMedia(
        string memory _source, 
        string memory _externalId, 
        string memory _title, 
        string memory _metadataHash
    ) external onlyOwner {
        bytes32 mediaId = computeMediaId(_source, _externalId);
        _register(mediaId, _source, _externalId, _title, _metadataHash);
    }

    // --- DAO GOVERNANCE ---

    function proposeMedia(
        string memory _source, 
        string memory _externalId, 
        string memory _title, 
        string memory _metadataHash
    ) external {
        bytes32 mediaId = computeMediaId(_source, _externalId);
        require(mediaEntries[mediaId].id == bytes32(0), "Media already exists");
        require(proposals[mediaId].deadline == 0, "Proposal already active");

        // Optional: Require Stake to Propose?
        require(waraToken.balanceOf(msg.sender) > 0, "Must hold WARA to propose");

        proposals[mediaId] = Proposal({
            upvotes: 0,
            downvotes: 0,
            deadline: block.timestamp + VOTING_PERIOD,
            proposer: msg.sender,
            snapshotBlock: block.number,
            executed: false
        });
        
        emit ProposalCreated(mediaId, _source, _externalId, _title, block.timestamp + VOTING_PERIOD);
    }

    function vote(string memory _source, string memory _externalId, int8 _side) external {
        bytes32 mediaId = computeMediaId(_source, _externalId);
        Proposal storage p = proposals[mediaId];
        
        require(p.deadline > 0, "Proposal not found");
        require(block.timestamp < p.deadline, "Voting closed");
        require(!hasVoted[mediaId][msg.sender], "Already voted");
        
        uint256 weight = IVotes(address(waraToken)).getPastVotes(msg.sender, p.snapshotBlock);
        require(weight > 0, "No voting power (must hold WARA at snapshot)");

        require(_side == 1 || _side == -1, "Invalid vote");

        hasVoted[mediaId][msg.sender] = true;

        if (_side == 1) {
            p.upvotes += weight;
        } else {
            p.downvotes += weight;
        }

        emit Voted(mediaId, msg.sender, _side);
    }

    function resolveProposal(
        string memory _source, 
        string memory _externalId, 
        string memory _title, 
        string memory _metadataHash
    ) external {
        bytes32 mediaId = computeMediaId(_source, _externalId);
        Proposal storage p = proposals[mediaId];

        require(p.deadline > 0, "Proposal not found");
        require(!p.executed, "Already executed");
        require(block.timestamp >= p.deadline, "Voting period not returned");

        p.executed = true;

        // Check Quorum
        uint256 totalVotes = p.upvotes + p.downvotes;
        uint256 totalSupplySnapshot = IVotes(address(waraToken)).getPastTotalSupply(p.snapshotBlock);
        uint256 minQuorum = (totalSupplySnapshot * QUORUM_PERCENT) / 100;

        require(totalVotes >= minQuorum, "Quorum not reached");

        if (p.upvotes > p.downvotes) {
            // Success
            _register(mediaId, _source, _externalId, _title, _metadataHash);
            emit ProposalExecuted(mediaId, true);
            
            // Reward
            if (waraToken.balanceOf(address(this)) >= EXECUTION_REWARD) {
                waraToken.transfer(msg.sender, EXECUTION_REWARD);
            }
        } else {
            // Rejected
            emit ProposalExecuted(mediaId, false);
        }
    }

    // --- INTERNAL ---

    function _register(bytes32 mediaId, string memory _source, string memory _externalId, string memory _title, string memory _metadataHash) internal {
        require(mediaEntries[mediaId].id == bytes32(0), "Media exists");
         mediaEntries[mediaId] = MediaEntry({
            id: mediaId,
            source: _source,
            externalId: _externalId,
            title: _title,
            metadataHash: _metadataHash,
            active: true,
            createdAt: block.timestamp
        });
        emit MediaRegistered(mediaId, _source, _externalId, _title);
    }

    // --- VIEW ---
    function getMedia(bytes32 _mediaId) external view returns (MediaEntry memory) {
        return mediaEntries[_mediaId];
    }
    
    function exists(string memory _source, string memory _externalId) external view returns (bool, bytes32) {
        bytes32 id = computeMediaId(_source, _externalId);
        return (mediaEntries[id].id != bytes32(0), id);
    }
}
