// SPDX-License-Identifier: MIT
// Wara Network - LinkRegistry
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IGasPool {
    function refillGas(address recipient, uint256 amount) external;
}

contract LinkRegistry {
    using ECDSA for bytes32;
    
    struct LinkData {
        uint256 upvotes;
        uint256 downvotes;
        uint256 trustScore; // 0-100
        address hoster; // Wallet that uploaded this link
        bytes32 contentHash; // SHA256 of the content
        mapping(address => int8) votes; // voter => vote value (-1, 0, 1)
    }
    
    // linkId (bytes32 hash of local node ID) => LinkData
    mapping(bytes32 => LinkData) public links;
    
    // tmdbId => array of linkIds (for content grouping)
    mapping(bytes32 => bytes32[]) public linksByMediaHash;

    // Track if a link has already paid out a report reward
    mapping(bytes32 => bool) public reportedLinks;

    // Global Content Ranking: contentHash => score
    mapping(bytes32 => uint256) public contentUpvotes;
    mapping(bytes32 => uint256) public contentDownvotes;
    mapping(bytes32 => uint256) public contentTrustScore;
    
    // Processed signatures to prevent double spending
    mapping(bytes32 => bool) public processedSignatures;
    
    // Reference to Leaderboard contract
    address public LeaderBoardContract;
    address public gasPool;
    uint256 public gasSubsidyUnit = 0.005 ether;
    address public authorizedOracle; // The oracle allowed to trigger rewards
    
    // Reward settings
    IERC20 public rewardToken;
    uint256 public constant VOTE_REWARD = 1 * 10**17; // 0.1 WARA tokens to Relayer
    
    // Link ID Composition:
    // linkId = keccak256(abi.encodePacked(contentHash, uploaderWallet, salt, mediaHash))
    // This ensures uniqueness per upload instance.
    
    event Voted(
        bytes32 indexed linkId,
        bytes32 indexed contentHash,
        address indexed voter,
        int8 value,
        uint256 newTrustScore
    );
    
    event LinkRegistered(
        bytes32 indexed linkId,
        bytes32 indexed contentHash,
        bytes32 mediaHash,
        address indexed hoster,
        string salt
    );
    
    constructor(address _LeaderBoardContract, address _rewardToken, address _gasPool) {
        LeaderBoardContract = _LeaderBoardContract;
        rewardToken = IERC20(_rewardToken);
        gasPool = _gasPool;
    }
    
    /**
     * @notice Register a new link (called when link is created)
     * @param contentHash SHA256 of the content (video file POV)
     * @param mediaHash WaraID of the movie/show from MediaRegistry
     * @param salt Unique random string for this upload
     * @param hoster Wallet address of the uploader
     */
    function registerLink(
        bytes32 contentHash,
        bytes32 mediaHash,
        string calldata salt, // Unique per upload instance
        address hoster
    ) external returns (bytes32) {
        require(hoster != address(0), "Invalid hoster address");
        
        // Formula acorde al diseño: Hash + Hoster + Salt + MediaHash
        bytes32 linkId = keccak256(abi.encodePacked(contentHash, hoster, salt, mediaHash));

        require(links[linkId].hoster == address(0), "Link ID collision/Already registered");
        
        LinkData storage link = links[linkId];
        link.hoster = hoster;
        link.contentHash = contentHash;
        link.trustScore = 50;
        
        // Add to Media Group
        linksByMediaHash[mediaHash].push(linkId);
        
        // Auto-Refill Gas for active hoster
        _triggerGasRefill(hoster);

        emit LinkRegistered(linkId, contentHash, mediaHash, hoster, salt);
        return linkId;
    }

    function _triggerGasRefill(address hoster) internal {
        if (gasPool != address(0)) {
            try IGasPool(gasPool).refillGas(hoster, gasSubsidyUnit) {} catch {}
        }
    }
    
    /**
     * @notice Vote on a link (upvote = 1, downvote = -1)
     * @param linkId Unique identifier for the link
     * @param value Vote value (1 or -1)
     */
    /**
     * @notice Vote on a link (upvote = 1, downvote = -1)
     * @param linkId Unique identifier for the link
     * @param value Vote value (1 or -1)
     */
    function vote(bytes32 linkId, int8 value) external {
        require(value == 1 || value == -1, "Vote must be 1 or -1");
        
        LinkData storage link = links[linkId];
        require(link.hoster != address(0), "Link not registered");
        require(link.hoster != msg.sender, "Cannot vote on own link");
        
        int8 previousVote = link.votes[msg.sender];
        
        // Update vote counts
        if (previousVote == 1) {
            link.upvotes--;
        } else if (previousVote == -1) {
            link.downvotes--;
        }
        
        if (value == 1) {
            link.upvotes++;
        } else {
            link.downvotes++;
        }
        
        // Store new vote
        link.votes[msg.sender] = value;
        
        // Recalculate trust score
        uint256 totalVotes = link.upvotes + link.downvotes;
        if (totalVotes > 0) {
            link.trustScore = (link.upvotes * 100) / totalVotes;
        } else {
            link.trustScore = 50; 
        }

        // Update Global Content Stats
        if (link.contentHash != bytes32(0)) {
            if (previousVote == 1) contentUpvotes[link.contentHash]--;
            else if (previousVote == -1) contentDownvotes[link.contentHash]--;

            if (value == 1) contentUpvotes[link.contentHash]++;
            else if (value == -1) contentDownvotes[link.contentHash]++;

            uint256 globalTotal = contentUpvotes[link.contentHash] + contentDownvotes[link.contentHash];
            if (globalTotal > 0) {
                contentTrustScore[link.contentHash] = (contentUpvotes[link.contentHash] * 100) / globalTotal;
            }
        }
        
        emit Voted(linkId, link.contentHash, msg.sender, value, link.trustScore);
        
        // Notify LeaderBoard contract
        if (LeaderBoardContract != address(0)) {
            (bool success,) = LeaderBoardContract.call(
                abi.encodeWithSignature(
                    "updateHosterScore(address,int8,int8)",
                    link.hoster,
                    value,
                    previousVote
                )
            );
            if (!success) {
                emit HosterUpdateFailed(link.hoster, value, previousVote);
            }
        }
    }
    
    event HosterUpdateFailed(address hoster, int8 newVote, int8 oldVote);
    
    /**
     * @notice Get trust score for a link
     * @param linkId Unique identifier for the link
     * @return trustScore Score from 0-100
     */
    function getTrustScore(bytes32 linkId) external view returns (uint256) {
        return links[linkId].trustScore;
    }
    
    /**
     * @notice Get vote counts for a link
     * @param linkId Unique identifier for the link
     * @return upvotes Number of upvotes
     * @return downvotes Number of downvotes
     * @return trustScore Current trust score
     */
    function getLinkStats(bytes32 linkId) external view returns (
        uint256 upvotes,
        uint256 downvotes,
        uint256 trustScore,
        address hoster
    ) {
        LinkData storage link = links[linkId];
        return (link.upvotes, link.downvotes, link.trustScore, link.hoster);
    }
    
    /**
     * @notice Get links ranked by trust score for a specific content
     * @param mediaHash WaraID to get links for
     * @return rankedLinks Array of linkIds sorted by trust score (highest first)
     */
    function getLinksRanked(bytes32 mediaHash) external view returns (bytes32[] memory) {
        bytes32[] memory linkHashes = linksByMediaHash[mediaHash];
        uint256 length = linkHashes.length;
        
        if (length == 0) {
            return new bytes32[](0);
        }
        
        // Create array of (linkHash, trustScore) for sorting
        bytes32[] memory ranked = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            ranked[i] = linkHashes[i];
        }
        
        // Bubble sort by trust score (descending)
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (links[ranked[j]].trustScore < links[ranked[j + 1]].trustScore) {
                    bytes32 temp = ranked[j];
                    ranked[j] = ranked[j + 1];
                    ranked[j + 1] = temp;
                }
            }
        }
        
        return ranked;
    }
    
    /**
     * @notice Get user's vote on a link
     * @param linkId Unique identifier for the link
     * @param voter Wallet address of the voter
     * @return vote Vote value (-1, 0, or 1)
     */
    function getUserVote(bytes32 linkId, address voter) external view returns (int8) {
        return links[linkId].votes[voter];
    }
    
    /**
     * @notice Vote on a link using a gasless signature (called by Hoster or Relayer)
     * @param linkId Unique identifier for the link
     * @param value Vote value (1 or -1)
     * @param voter Address of the user who signed the vote
     * @param nonce Unique random number for the signature
     * @param timestamp Time when the vote was signed
     * @param signature Cryptographic signature for verification
     */
    function _voteWithSignature(
        bytes32 linkId,
        bytes32 contentHash,
        int8 value,
        address voter,
        address relayer,
        uint256 nonce,
        uint256 timestamp,
        bytes calldata signature
    ) internal {
        require(value == 1 || value == -1, "Vote must be 1 or -1");
        require(voter != address(0), "Invalid voter address");
        require(relayer != address(0), "Invalid relayer address");
        
        // 1. Verify Signature: User must sign (linkId, contentHash, value, voter, relayer, nonce, timestamp)
        bytes32 messageHash = keccak256(abi.encodePacked(linkId, contentHash, value, voter, relayer, nonce, timestamp));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        
        require(!processedSignatures[ethSignedMessageHash], "Signature already processed");
        processedSignatures[ethSignedMessageHash] = true;
        
        address signer = ethSignedMessageHash.recover(signature);
        require(signer == voter, "Invalid signature");
        
        // 2. Voting Logic (Internal)
        LinkData storage link = links[linkId];
        require(link.hoster != address(0), "Link not registered");

        int8 previousVote = link.votes[voter];
        // require(previousVote != value, "Already voted this way"); // Soft fail in batch?
        if (previousVote == value) return; // Skip if already voted same

        // Remove old vote
        if (previousVote == 1) link.upvotes--;
        else if (previousVote == -1) link.downvotes--;

        // Add new vote
        if (value == 1) link.upvotes++;
        else if (value == -1) link.downvotes++;

        link.votes[voter] = value;

        // Recalculate trust score
        uint256 totalVotes = link.upvotes + link.downvotes;
        if (totalVotes > 0) {
            link.trustScore = (link.upvotes * 100) / totalVotes;
        }

        // Update Global Content Stats
        if (link.contentHash != bytes32(0)) {
            if (previousVote == 1) contentUpvotes[link.contentHash]--;
            else if (previousVote == -1) contentDownvotes[link.contentHash]--;

            if (value == 1) contentUpvotes[link.contentHash]++;
            else if (value == -1) contentDownvotes[link.contentHash]++;

            uint256 globalTotal = contentUpvotes[link.contentHash] + contentDownvotes[link.contentHash];
            if (globalTotal > 0) {
                contentTrustScore[link.contentHash] = (contentUpvotes[link.contentHash] * 100) / globalTotal;
            }
        }

        emit Voted(linkId, link.contentHash, voter, value, link.trustScore);

        // 3. Reward Relayer (Only for negative votes / reports)
        if (value == -1 && address(rewardToken) != address(0)) {
            uint256 balance = rewardToken.balanceOf(address(this));
            if (balance >= VOTE_REWARD) {
                rewardToken.transfer(relayer, VOTE_REWARD);
            }
        }

        // 4. Update Hoster Reputation
        if (LeaderBoardContract != address(0) && link.hoster != address(0)) {
            (bool success,) = LeaderBoardContract.call(
                abi.encodeWithSignature(
                    "updateHosterScore(address,int8,int8)",
                    link.hoster,
                    value,
                    previousVote
                )
            );
            if (!success) {
                emit HosterUpdateFailed(link.hoster, value, previousVote);
            }
        }
    }

    /**
     * @notice Vote on a link using a gasless signature (Singular)
     */
    function voteWithSignature(
        bytes32 linkId,
        bytes32 contentHash,
        int8 value,
        address voter,
        address relayer,
        uint256 nonce,
        uint256 timestamp,
        bytes calldata signature
    ) external {
        _voteWithSignature(linkId, contentHash, value, voter, relayer, nonce, timestamp, signature);
    }

    /**
     * @notice Batch Vote with Signature (Gas Optimized)
     */
    function batchVoteWithSignature(
        bytes32[] calldata linkIds,
        bytes32[] calldata contentHashes,
        int8[] calldata values,
        address[] calldata voters,
        address[] calldata relayers,
        uint256[] calldata nonces,
        uint256[] calldata timestamps,
        bytes[] calldata signatures
    ) external {
        require(
            linkIds.length == contentHashes.length &&
            contentHashes.length == values.length &&
            values.length == voters.length &&
            voters.length == relayers.length &&
            relayers.length == nonces.length &&
            nonces.length == timestamps.length &&
            timestamps.length == signatures.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < linkIds.length; i++) {
            _voteWithSignature(
                linkIds[i],
                contentHashes[i],
                values[i],
                voters[i],
                relayers[i],
                nonces[i],
                timestamps[i],
                signatures[i]
            );
        }
    }

    /**
     * @notice Update LeaderBoard contract address (admin only)
     * @param newAddress New contract address
     */
    function setLeaderBoardContract(address newAddress) external {
        // TODO: Add access control (Ownable)
        LeaderBoardContract = newAddress;
    }

    /**
     * @notice Set Reward Token address (admin only)
     * @param newAddress Token address
     */
    function setRewardToken(address newAddress) external {
        // TODO: Add access control
        rewardToken = IERC20(newAddress);
    }

    /**
     * @notice Pay reward to an oracle judge
     * @param judge Wallet of the judge
     * @param amount Amount of WARA to pay
     */
    function payOracleReward(address judge, uint256 amount) external {
        require(msg.sender == authorizedOracle, "Not authorized oracle");
        require(address(rewardToken) != address(0), "Reward token not set");
        
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance >= amount, "Insufficient reward pool in LinkRegistry");
        
        rewardToken.transfer(judge, amount);
    }

    function setAuthorizedOracle(address _oracle) external {
        // TODO: Add access control
        authorizedOracle = _oracle;
    }

    function setGasPool(address _gasPool, uint256 _subsidy) external {
        gasPool = _gasPool;
        gasSubsidyUnit = _subsidy;
    }
}
