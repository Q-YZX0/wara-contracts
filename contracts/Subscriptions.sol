// SPDX-License-Identifier: MIT
// Wara Network - Subscriptions
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./AggregatorV3Interface.sol";

contract Subscriptions is Ownable, ReentrancyGuard {
    IERC20 public immutable waraToken;
    AggregatorV3Interface public priceFeed;

    uint256 public constant MONTHLY_PRICE_USD = 5e18; // $5 USD
    uint256 public constant SUBSCRIPTION_DURATION = 30 days;

    uint256 public constant HOSTER_POOL_SHARE = 70;
    uint256 public constant TREASURY_SHARE = 20;
    uint256 public constant CREATOR_SHARE = 10;

    // --- Dynamic Payment Config ---
    uint256 public constant BASE_PAYMENT_PER_VIEW = 0.005 ether; // 0.005 WARA (Min)
    uint256 public constant MAX_PAYMENT_PER_VIEW = 0.01 ether;   // 0.01 WARA (Max)
    uint256 public constant POOL_HEALTH_THRESHOLD = 500 ether;   // 500 WARA considered "healthy"

    address public treasury;
    address public protocolCreator;

    struct Subscription {
        uint256 expiresAt;
        uint256 totalPaid;
        uint256 subscriptionCount;
    }
    mapping(address => Subscription) public subscriptions;

    // Hoster accounting
    uint256 public hosterPoolBalance;
    mapping(address => uint256) public accumulatedRewards; 
    mapping(uint256 => bool) public processedNonces;
    uint256 public totalPremiumViews;

    uint256 public totalSubscribers;
    uint256 public totalRevenue;

    event Subscribed(address indexed user, uint256 expiresAt, uint256 paidWARA);
    event HosterRewardClaimed(address indexed hoster, uint256 amount);
    event PremiumViewRecorded(address indexed hoster, address indexed viewer, uint256 payment);

    constructor(address _waraToken, address _priceFeed, address _treasury, address _protocolCreator) Ownable(msg.sender) {
        waraToken = IERC20(_waraToken);
        priceFeed = AggregatorV3Interface(_priceFeed);
        treasury = _treasury;
        protocolCreator = _protocolCreator;
    }

    function subscribe() external nonReentrant {
        uint256 priceInWARA = getCurrentPrice();
        require(waraToken.transferFrom(msg.sender, address(this), priceInWARA), "Transfer failed");

        // --- DEFLATIONARY BURN ---
        // Burn 10% of the subscription price
        // Limit: Only burn if total supply is > 650M (65% of initial 1B)
        uint256 burnAmount = 0;
        uint256 currentSupply = ERC20Burnable(address(waraToken)).totalSupply();

        if (currentSupply > 650_000_000 * 10**18) {
            burnAmount = (priceInWARA * 10) / 100;
            if (burnAmount > 0) {
                try ERC20Burnable(address(waraToken)).burn(burnAmount) {} catch {}
            }
        }
        uint256 remainingRevenue = priceInWARA - burnAmount;

        uint256 hosterPoolAmount = (remainingRevenue * HOSTER_POOL_SHARE) / 100;
        uint256 treasuryAmount = (remainingRevenue * TREASURY_SHARE) / 100;
        uint256 creatorAmount = (remainingRevenue * CREATOR_SHARE) / 100;

        require(waraToken.transfer(treasury, treasuryAmount), "Treasury fail");
        require(waraToken.transfer(protocolCreator, creatorAmount), "Creator fail");

        // Add to pool (Reserva)
        hosterPoolBalance += hosterPoolAmount;

        Subscription storage sub = subscriptions[msg.sender];
        if (sub.expiresAt > block.timestamp) {
            sub.expiresAt += SUBSCRIPTION_DURATION;
        } else {
            sub.expiresAt = block.timestamp + SUBSCRIPTION_DURATION;
            sub.subscriptionCount++;
            totalSubscribers++;
        }
        sub.totalPaid += priceInWARA;
        totalRevenue += priceInWARA;
        
        emit Subscribed(msg.sender, sub.expiresAt, priceInWARA);
    }

    /**
     * @dev Records a premium view and rewards the hoster.
     * Uses ECDSA signature from the viewer to authorize the payment.
     */
    function recordPremiumView(
        address hoster, 
        address viewer, 
        bytes32 contentHash,
        uint256 nonce,
        bytes calldata signature
    ) external nonReentrant {
        require(isSubscribed(viewer), "User not subscribed");
        require(!processedNonces[nonce], "Nonce already used");

        // Verify Signature: viewer must sign (hoster, viewer, contentHash, nonce, chainId)
        bytes32 messageHash = keccak256(abi.encodePacked(hoster, viewer, contentHash, nonce, block.chainid));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        
        address signer = ECDSA.recover(ethSignedMessageHash, signature);
        require(signer == viewer, "Invalid signature from viewer");

        processedNonces[nonce] = true;

        // --- DYNAMIC PAYMENT LOGIC ---
        uint256 payment = BASE_PAYMENT_PER_VIEW;
        
        if (hosterPoolBalance > POOL_HEALTH_THRESHOLD) {
            payment = MAX_PAYMENT_PER_VIEW;
        } else if (hosterPoolBalance > (POOL_HEALTH_THRESHOLD / 2)) {
            payment = (BASE_PAYMENT_PER_VIEW + MAX_PAYMENT_PER_VIEW) / 2;
        }

        require(hosterPoolBalance >= payment, "Insufficient pool balance");
        
        hosterPoolBalance -= payment;
        accumulatedRewards[hoster] += payment;
        totalPremiumViews++;
        
        emit PremiumViewRecorded(hoster, viewer, payment);
    }

    function claimHosterReward() external nonReentrant {
        uint256 reward = accumulatedRewards[msg.sender];
        require(reward > 0, "No rewards accumulated");

        accumulatedRewards[msg.sender] = 0;
        require(waraToken.transfer(msg.sender, reward), "Transfer failed");

        emit HosterRewardClaimed(msg.sender, reward);
    }

    // --- Helpers ---
    function isSubscribed(address user) public view returns (bool) {
        return subscriptions[user].expiresAt > block.timestamp;
    }

    function getCurrentPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        uint8 decimals = priceFeed.decimals();
        return (MONTHLY_PRICE_USD * (10 ** decimals)) / uint256(price);
    }

    function getPendingReward(address hoster) external view returns (uint256) {
        return accumulatedRewards[hoster];
    }
    
    function getSubscription(address user) external view returns (bool active, uint256 expiresAt, uint256 daysRemaining, uint256 totalPaid, uint256 subscriptionCount) {
        Subscription storage sub = subscriptions[user];
        active = sub.expiresAt > block.timestamp;
        expiresAt = sub.expiresAt;
        daysRemaining = active ? (sub.expiresAt - block.timestamp) / 1 days : 0;
        totalPaid = sub.totalPaid;
        subscriptionCount = sub.subscriptionCount;
    }
    
    function getStats() external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (totalSubscribers, totalRevenue, hosterPoolBalance, totalPremiumViews, getCurrentPrice());
    }

    // Batch support removed in favor of security and gas efficiency per record
    // Recommended to be called by a relay or individual hosters
}
