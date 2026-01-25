// SPDX-License-Identifier: MIT
// Wara Network - AdManager
// Developed by YZX0 (https://github.com/Q-YZX0)
// "Unstoppable Streaming, Community-Owned Content."
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Wara Oracle Interface
interface IWaraOracle {
    function latestAnswer() external view returns (int256);
}
import "./LinkRegistry.sol";

/**
 * @title AdManager
 * @notice Manages advertising campaigns with USD-based pricing
 * @dev Uses Chainlink price feeds to convert USD to WARA tokens
 */
contract AdManager is Ownable {
    using ECDSA for bytes32;

    IERC20 public waraToken;
    IWaraOracle public priceFeed; // WARA/USD native price feed
    
    // Burning Mechanism: 10% of every ad campaign is burned
    uint256 public constant BURN_FEE_PERCENT = 10;
    
    // $0.01 USD per second (in 18 decimals)
    uint256 public constant USD_PER_SECOND = 1e16; // 0.01 * 1e18
    
    enum Category { General, Political, Sensitive }

    struct AdCampaign {
        address advertiser;
        uint256 budgetWARA; // Budget in WARA tokens
        uint8 duration; // 5-45 seconds
        string videoHash; // IPFS hash of the ad video
        uint256 viewsRemaining; // Guaranteed views
        Category category;
        bool active;
    }

    mapping(uint256 => AdCampaign) public campaigns;
    uint256 public nextCampaignId;
    uint256 public activeCampaignCount;

    address public linkReputation;

    // Prevent double spending of signatures
    mapping(bytes32 => bool) public processedSignatures;

    event CampaignCreated(
        uint256 indexed id,
        address indexed advertiser,
        uint256 budgetWARA,
        uint256 viewsGuaranteed,
        uint8 duration,
        Category category
    );
    
    event AdViewed(
        uint256 indexed campaignId,
        address indexed uploader,
        address indexed viewer,
        uint256 rewardWARA
    );

    constructor(
        address _tokenAddress,
        address _priceFeedAddress
    ) Ownable(msg.sender) {
        waraToken = IERC20(_tokenAddress);
        priceFeed = IWaraOracle(_priceFeedAddress);
    }

    /**
     * @notice Create a new ad campaign
     * @param budgetWARA Total budget in WARA tokens
     * @param duration Ad duration in seconds (5-45)
     * @param videoHash IPFS hash of the ad video
     */
    function createCampaign(
        uint256 budgetWARA,
        uint8 duration,
        string memory videoHash,
        Category category
    ) external {
        require(budgetWARA > 0, "Budget must be > 0");
        require(duration >= 5 && duration <= 45, "Duration must be 5-45s");
        require(bytes(videoHash).length > 0, "Video hash required");

        // Get current WARA price in USD from our Oracle
        int256 price = priceFeed.latestAnswer();
        require(price > 0, "Invalid price");
        
        uint256 waraPriceUSD = uint256(price); // e.g., $2.50 = 250000000 (8 decimals)
        
        // Calculate cost per view in USD
        uint256 costPerViewUSD = USD_PER_SECOND * duration; // $0.01 * duration
        
        // Convert to WARA (adjust decimals: 18 - 8 = 10)
        // costPerViewWARA = (costPerViewUSD * 1e8) / waraPriceUSD
        uint256 costPerViewWARA = (costPerViewUSD * 1e8) / waraPriceUSD;
        
        // Calculate guaranteed views
        uint256 viewsGuaranteed = budgetWARA / costPerViewWARA;
        require(viewsGuaranteed > 0, "Budget too low for even 1 view");

        // Transfer budget from advertiser
        require(
            waraToken.transferFrom(msg.sender, address(this), budgetWARA),
            "Transfer failed"
        );

        // --- DEFLATIONARY BURN ---
        // Burn 10% of the total budget to increase WARA value
        // Limit: Only burn if total supply is > 650M (65% of initial 1B)
        uint256 burnAmount = 0;
        uint256 currentSupply = ERC20Burnable(address(waraToken)).totalSupply();
        
        if (currentSupply > 650_000_000 * 10**18) {
            burnAmount = (budgetWARA * BURN_FEE_PERCENT) / 100;
            if (burnAmount > 0) {
                try ERC20Burnable(address(waraToken)).burn(burnAmount) {} catch {}
            }
        }
        uint256 finalBudget = budgetWARA - burnAmount;

        campaigns[nextCampaignId] = AdCampaign({
            advertiser: msg.sender,
            budgetWARA: finalBudget, // Net budget after burn
            duration: duration,
            videoHash: videoHash,
            viewsRemaining: viewsGuaranteed,
            category: category,
            active: true
        });

        emit CampaignCreated(
            nextCampaignId,
            msg.sender,
            budgetWARA,
            viewsGuaranteed,
            duration,
            category
        );
        
        activeCampaignCount++;
        nextCampaignId++;
    }

    /**
     * @notice Claim reward for serving an ad (called by host node)
     * @param campaignId ID of the campaign
     * @param viewer Address of the viewer who watched the ad
     * @param signature Signature from viewer confirming they watched
     */
    /**
     * @notice Internal logic for claiming ad view
     */
    function _claimAdView(
        uint256 campaignId,
        address viewer,
        bytes32 contentHash,
        bytes32 linkId,
        bytes memory signature
    ) internal {
        require(linkReputation != address(0), "Reputation contract not set");
        
        // RESOLVE UPLOADER FROM BLOCKCHAIN (Bypasses frontend manipulation)
        (,,,address uploaderWallet) = LinkRegistry(linkReputation).getLinkStats(linkId);
        require(uploaderWallet != address(0), "Link not registered on-chain");
        
        AdCampaign storage campaign = campaigns[campaignId];
        // Skip instead of revert in batch? For security, revert singular, maybe continue in batch?
        // For consistency: Require active.
        require(campaign.active, "Campaign inactive");
        require(campaign.viewsRemaining > 0, "Views exhausted");

        // Reconstruct message (Secure: includes ChainID and Contract Address)
        bytes32 messageHash = keccak256(
            abi.encodePacked(campaignId, uploaderWallet, viewer, contentHash, linkId, block.chainid, address(this))
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Verify signature
        address signer = ECDSA.recover(ethSignedMessageHash, signature);
        require(signer == viewer, "Invalid signature");

        // Prevent replay attacks
        require(!processedSignatures[ethSignedMessageHash], "Signature already used");
        processedSignatures[ethSignedMessageHash] = true;

        // Recalculate reward
        int256 price = priceFeed.latestAnswer();
        uint256 waraPriceUSD = uint256(price);
        
        uint256 costPerViewUSD = USD_PER_SECOND * campaign.duration;
        uint256 reward = (costPerViewUSD * 1e8) / waraPriceUSD;
        
        uint256 budgetPerView = campaign.budgetWARA / campaign.viewsRemaining;
        if (reward > budgetPerView) {
            reward = budgetPerView;
        }

        // Update campaign state
        campaign.viewsRemaining--;
        campaign.budgetWARA -= reward;

        // Deactivate if exhausted
        if (campaign.viewsRemaining == 0) {
            campaign.active = false;
            if (activeCampaignCount > 0) activeCampaignCount--;
            
            // Refund remaining budget
            if (campaign.budgetWARA > 0) {
                require(
                    waraToken.transfer(campaign.advertiser, campaign.budgetWARA),
                    "Refund failed"
                );
            }
        }

        // Pay the content uploader
        require(waraToken.transfer(uploaderWallet, reward), "Payment failed");

        emit AdViewed(campaignId, uploaderWallet, viewer, reward);

    }

    /**
     * @notice Claim reward for serving an ad (single)
     */
    function claimAdView(
        uint256 campaignId,
        address viewer,
        bytes32 contentHash,
        bytes32 linkId,
        bytes memory signature
    ) external {
        _claimAdView(campaignId, viewer, contentHash, linkId, signature);
    }

    /**
     * @notice Batch claim rewards for serving ads
     */
    function batchClaimAdView(
        uint256[] calldata campaignIds,
        address[] calldata viewers,
        bytes32[] calldata contentHashes,
        bytes32[] calldata linkIds,
        bytes[] calldata signatures
    ) external {
        require(
            campaignIds.length == viewers.length &&
            viewers.length == contentHashes.length &&
            contentHashes.length == linkIds.length &&
            linkIds.length == signatures.length,
            "Array lengths mismatch"
        );

        for (uint256 i = 0; i < campaignIds.length; i++) {
            _claimAdView(
                campaignIds[i],
                viewers[i],
                contentHashes[i],
                linkIds[i],
                signatures[i]
            );
        }
    }

    /**
     * @notice Get campaign details
     * @param campaignId ID of the campaign
     */
    function getCampaign(uint256 campaignId) external view returns (
        address advertiser,
        uint256 budgetWARA,
        uint8 duration,
        string memory videoHash,
        uint256 viewsRemaining,
        Category category,
        bool active
    ) {
        AdCampaign storage campaign = campaigns[campaignId];
        return (
            campaign.advertiser,
            campaign.budgetWARA,
            campaign.duration,
            campaign.videoHash,
            campaign.viewsRemaining,
            campaign.category,
            campaign.active
        );
    }

    /**
     * @notice Calculate current cost per view in WARA
     * @param duration Ad duration in seconds
     */
    function getCurrentCostPerView(uint8 duration) external view returns (uint256) {
        require(duration >= 5 && duration <= 45, "Duration must be 5-45s");
        
        int256 price = priceFeed.latestAnswer();
        require(price > 0, "Invalid price");
        
        uint256 waraPriceUSD = uint256(price);
        uint256 costPerViewUSD = USD_PER_SECOND * duration;
        
        return (costPerViewUSD * 1e8) / waraPriceUSD;
    }

    /**
     * @notice Update price feed address (admin only)
     * @param newPriceFeed New Chainlink price feed address
     */
    function setPriceFeed(address newPriceFeed) external onlyOwner {
        require(newPriceFeed != address(0), "Invalid address");
        priceFeed = IWaraOracle(newPriceFeed);
    }

    /**
     * @notice Set LinkReputation contract address
     */
    function setLinkReputation(address _linkReputation) external onlyOwner {
        linkReputation = _linkReputation;
    }

    /**
     * @notice Get number of active campaigns
     */
    function getActiveCampaignCount() external view returns (uint256) {
        return activeCampaignCount;
    }
    /**
     * @notice Cancel a campaign and refund remaining budget
     * @param campaignId ID of the campaign to cancel
     */
    function cancelCampaign(uint256 campaignId) external {
        AdCampaign storage campaign = campaigns[campaignId];
        require(msg.sender == campaign.advertiser, "Not the advertiser");
        
        // Check Banned Status
        bool isBanned = adReporters[campaignId].length >= REPORT_THRESHOLD;
        require(!isBanned, "Campaign is banned");

        if (campaign.active) {
            campaign.active = false;
            if (activeCampaignCount > 0) activeCampaignCount--;
        }
        
        // Refund
        uint256 refundAmount = campaign.budgetWARA;
        if (refundAmount > 0) {
            campaign.budgetWARA = 0;
            campaign.viewsRemaining = 0;
            require(waraToken.transfer(msg.sender, refundAmount), "Refund failed");
        }
    }

    /**
     * @notice Toggle campaign status (Pause/Resume) without refund
     * @param campaignId ID of the campaign
     */
    function togglePause(uint256 campaignId) external {
        AdCampaign storage campaign = campaigns[campaignId];
        require(msg.sender == campaign.advertiser, "Not the advertiser");
        
        bool isBanned = adReporters[campaignId].length >= REPORT_THRESHOLD;
        require(!isBanned, "Campaign is banned");

        if (campaign.active) {
            campaign.active = false;
            if (activeCampaignCount > 0) activeCampaignCount--;
        } else {
            // Can only resume if has budget/views
            require(campaign.viewsRemaining > 0, "No views remaining");
            campaign.active = true;
            activeCampaignCount++;
        }
    }

    /**
     * @notice Add funds to an existing campaign
     * @param campaignId ID of the campaign
     * @param amount Amount of WARA to add
     */
    function topUpCampaign(uint256 campaignId, uint256 amount) external {
        AdCampaign storage campaign = campaigns[campaignId];
        require(msg.sender == campaign.advertiser, "Not the advertiser");
        require(amount > 0, "Amount must be > 0");

        // Transfer tokens
        require(waraToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Update budget
        campaign.budgetWARA += amount;

        // Recalculate added views based on CURRENT price
        int256 price = priceFeed.latestAnswer();
        uint256 waraPriceUSD = uint256(price);
        uint256 costPerViewUSD = USD_PER_SECOND * campaign.duration;
        uint256 costPerViewWARA = (costPerViewUSD * 1e8) / waraPriceUSD;
        
        uint256 newViews = amount / costPerViewWARA;
        campaign.viewsRemaining += newViews;

        // Reactivate if it was inactive
        if (!campaign.active && campaign.viewsRemaining > 0) {
            campaign.active = true;
            activeCampaignCount++;
        }
    }

    // --- Moderation System ---
    uint256 public constant REPORT_THRESHOLD = 5; // Votes to pause an ad

    // Campaign ID -> List of Reporters
    mapping(uint256 => address[]) public adReporters;
    // Campaign ID -> Reporter -> Has Reported?
    mapping(uint256 => mapping(address => bool)) public hasReported;

    event AdReported(uint256 indexed campaignId, address indexed reporter, uint8 reasonCode);
    event AdPausedByCommunity(uint256 indexed campaignId);

    /**
     * @notice Report a malicious or miscategorized ad
     * @param campaignId The ID of the ad campaign
     * @param reasonCode 0: Malicious, 1: Wrong Category, 2: Illegal, 3: Spam
     */
    function reportAd(uint256 campaignId, uint8 reasonCode) external {
        require(campaignId < nextCampaignId, "Invalid campaign ID");
        require(!hasReported[campaignId][msg.sender], "Already reported");
        
        AdCampaign storage campaign = campaigns[campaignId];
        require(campaign.active, "Ad already inactive");

        // Record report
        hasReported[campaignId][msg.sender] = true;
        adReporters[campaignId].push(msg.sender);

        emit AdReported(campaignId, msg.sender, reasonCode);

        // Check Threshold
        if (adReporters[campaignId].length >= REPORT_THRESHOLD) {
            campaign.active = false;
            if (activeCampaignCount > 0) activeCampaignCount--;
            emit AdPausedByCommunity(campaignId);
        }
    }

    struct CampaignInfo {
        uint256 id;
        AdCampaign campaign;
    }

    /**
     * @notice Get all campaigns for a specific advertiser
     * @param advertiser Address of the advertiser
     */
    function getCampaignsByAdvertiser(address advertiser) external view returns (CampaignInfo[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextCampaignId; i++) {
            if (campaigns[i].advertiser == advertiser) {
                count++;
            }
        }

        CampaignInfo[] memory result = new CampaignInfo[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < nextCampaignId; i++) {
            if (campaigns[i].advertiser == advertiser) {
                result[index] = CampaignInfo({
                    id: i,
                    campaign: campaigns[i]
                });
                index++;
            }
        }
        return result;
    }

    /**
     * @notice Get audit info for an ad (reporters count)
     */
    function getReportCount(uint256 campaignId) external view returns (uint256) {
        return adReporters[campaignId].length;
    }
}
