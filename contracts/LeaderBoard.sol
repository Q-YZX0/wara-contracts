// SPDX-License-Identifier: MIT
// Wara Network - LeaderBoard
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LeaderBoard
 * @notice Global ranking system for content hosters/uploaders
 * @dev Aggregates votes from all links uploaded by each hoster
 */
contract LeaderBoard is Ownable {
    
    struct Hoster {
        uint256 totalLinks;
        uint256 totalUpvotes;
        uint256 totalDownvotes;
        uint256 averageScore; // 0-100
        uint256 rank; // Position in leaderboard (1 = best)
    }
    
    // hoster address => Hoster data
    mapping(address => Hoster) public hosters;
    
    // Leaderboard (sorted by averageScore)
    address[] public leaderboard;
    
    // Only LinkReputation contract can update scores
    address public LinkRegistryContract;
    bool public testMode; // For testing only
    
    event HosterScoreUpdated(
        address indexed hoster,
        uint256 newAverageScore,
        uint256 newRank
    );
    
    event HosterRegistered(
        address indexed hoster
    );
    
    modifier onlyLinkReputation() {
        require(testMode || msg.sender == LinkRegistryContract, "Only LinkReputation can call");
        _;
    }
    
    constructor(address _LinkRegistryContract) Ownable(msg.sender) {
        LinkRegistryContract = _LinkRegistryContract;
        testMode = false;
    }
    
    /**
     * @notice Enable test mode (ONLY FOR TESTING)
     */
    function enableTestMode() external {
        testMode = true;
    }
    
    /**
     * @notice Update hoster's score (called by LinkReputation when link is voted)
     * @param hoster Wallet address of the hoster
     * @param newVote New vote value (1 or -1)
     * @param oldVote Previous vote value (0 if new vote)
     */
    function updateHosterScore(address hoster, int8 newVote, int8 oldVote) external onlyLinkReputation {
        Hoster storage h = hosters[hoster];
        
        // Register hoster if new (check if not in leaderboard)
        bool isNew = (h.totalLinks == 0 && h.totalUpvotes == 0 && h.totalDownvotes == 0);
        if (isNew) {
            leaderboard.push(hoster);
            h.totalLinks = 1; // Mark as registered
            emit HosterRegistered(hoster);
        }
        
        // Remove old vote (with underflow protection)
        if (oldVote == 1 && h.totalUpvotes > 0) {
            h.totalUpvotes--;
        } else if (oldVote == -1 && h.totalDownvotes > 0) {
            h.totalDownvotes--;
        }
        
        // Add new vote
        if (newVote == 1) {
            h.totalUpvotes++;
        } else if (newVote == -1) {
            h.totalDownvotes++;
        }
        
        // Recalculate average score
        uint256 totalVotes = h.totalUpvotes + h.totalDownvotes;
        if (totalVotes > 0) {
            h.averageScore = (h.totalUpvotes * 100) / totalVotes;
        } else {
            h.averageScore = 50;
        }
        
        emit HosterScoreUpdated(hoster, h.averageScore, h.rank);
    }
    
    /**
     * @notice Manually register votes for a hoster (called by LinkReputation)
     * @param hoster Wallet address
     * @param upvotes Total upvotes
     * @param downvotes Total downvotes
     * @param linkCount Total links
     */
    function setHosterStats(
        address hoster,
        uint256 upvotes,
        uint256 downvotes,
        uint256 linkCount
    ) external onlyLinkReputation {
        Hoster storage h = hosters[hoster];
        
        // Register if new
        if (h.totalLinks == 0 && h.totalUpvotes == 0 && h.totalDownvotes == 0) {
            leaderboard.push(hoster);
            emit HosterRegistered(hoster);
        }
        
        h.totalLinks = linkCount;
        h.totalUpvotes = upvotes;
        h.totalDownvotes = downvotes;
        
        // Recalculate average score
        uint256 totalVotes = upvotes + downvotes;
        if (totalVotes > 0) {
            h.averageScore = (upvotes * 100) / totalVotes;
        } else {
            h.averageScore = 50;
        }
        
        emit HosterScoreUpdated(hoster, h.averageScore, h.rank);
    }
    
    /**
     * @notice Get hoster's rank
     * @param hoster Wallet address
     * @return rank Position in leaderboard (1 = best, 0 = not ranked)
     */
    function getHosterRank(address hoster) external view returns (uint256) {
        return hosters[hoster].rank;
    }
    
    /**
     * @notice Get hoster's stats
     * @param hoster Wallet address
     * @return totalLinks Number of links uploaded
     * @return totalUpvotes Total upvotes received
     * @return totalDownvotes Total downvotes received
     * @return averageScore Average quality score (0-100)
     * @return rank Position in leaderboard
     */
    function getHosterStats(address hoster) external view returns (
        uint256 totalLinks,
        uint256 totalUpvotes,
        uint256 totalDownvotes,
        uint256 averageScore,
        uint256 rank
    ) {
        Hoster storage h = hosters[hoster];
        return (h.totalLinks, h.totalUpvotes, h.totalDownvotes, h.averageScore, h.rank);
    }
    
    /**
     * @notice Get top hosters from leaderboard
     * @param limit Maximum number of hosters to return
     * @return topHosters Array of hoster addresses (sorted by rank)
     */
    function getLeaderboard(uint256 limit) external view returns (address[] memory) {
        uint256 length = leaderboard.length;
        uint256 resultLength = limit < length ? limit : length;
        
        address[] memory topHosters = new address[](resultLength);
        for (uint256 i = 0; i < resultLength; i++) {
            topHosters[i] = leaderboard[i];
        }
        
        return topHosters;
    }
    
    /**
     * @notice Get total number of hosters
     * @return count Total hosters in the system
     */
    function getTotalHosters() external view returns (uint256) {
        return leaderboard.length;
    }
    
    /**
     * @notice Update LinkRegistry contract address (admin only)
     * @param newAddress New contract address
     */
    function setLinkRegistryContract(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Invalid address");
        LinkRegistryContract = newAddress;
    }
}
