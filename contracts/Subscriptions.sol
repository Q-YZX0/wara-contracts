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

// Wara Oracle Interface
interface IWaraOracle {
    function latestAnswer() external view returns (int256);
}

contract Subscriptions is Ownable, ReentrancyGuard {
    IERC20 public waraToken;
    IWaraOracle public priceFeed;

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
    mapping(bytes32 => bool) public processedSignatures;
    uint256 public totalPremiumViews;

    uint256 public totalSubscribers;
    uint256 public totalRevenue;

    event Subscribed(address indexed user, uint256 expiresAt, uint256 paidWARA);
    event PremiumViewRecorded(address indexed hoster, address indexed viewer, uint256 payment);
    event PaymentFailed(address indexed hoster, uint256 amount);

    constructor(address _waraToken, address _priceFeed, address _treasury, address _protocolCreator) Ownable(msg.sender) {
        waraToken = IERC20(_waraToken);
        priceFeed = IWaraOracle(_priceFeed);
        treasury = _treasury;
        protocolCreator = _protocolCreator;
    }

    function setWaraToken(address _token) external onlyOwner {
        waraToken = IERC20(_token);
    }

    function setPriceFeed(address _feed) external onlyOwner {
        priceFeed = IWaraOracle(_feed);
    }

    function subscribe() external nonReentrant {
        uint256 priceInWARA = getCurrentPrice();
        require(waraToken.transferFrom(msg.sender, address(this), priceInWARA), "Transfer failed");

        // --- DEFLATIONARY BURN ---
        uint256 burnAmount = 0;
        uint256 currentSupply = ERC20Burnable(address(waraToken)).totalSupply();

        if (currentSupply > 650_000_000 * 10**18) {
            burnAmount = (priceInWARA * 10) / 100;
            if (burnAmount > 0) {
                try ERC20Burnable(address(waraToken)).burn(burnAmount) {} catch {}
            }
        }
        uint256 remainingRevenue = priceInWARA - burnAmount;

        uint256 treasuryAmount = (remainingRevenue * TREASURY_SHARE) / 100;
        uint256 creatorAmount = (remainingRevenue * CREATOR_SHARE) / 100;

        require(waraToken.transfer(treasury, treasuryAmount), "Treasury fail");
        require(waraToken.transfer(protocolCreator, creatorAmount), "Creator fail");

        totalRevenue += priceInWARA;

        Subscription storage sub = subscriptions[msg.sender];
        if (sub.expiresAt > block.timestamp) {
            sub.expiresAt += SUBSCRIPTION_DURATION;
        } else {
            sub.expiresAt = block.timestamp + SUBSCRIPTION_DURATION;
            sub.subscriptionCount++;
            totalSubscribers++;
        }
        sub.totalPaid += priceInWARA;

        emit Subscribed(msg.sender, sub.expiresAt, priceInWARA);
    }

    /**
     * @notice Records multiple premium views and pays hosters IMMEDIATELY in a single transaction (Batch).
     */
    function recordPremiumViewBatch(
        address[] calldata hosters,
        address[] calldata viewers,
        bytes32[] calldata contentHashes,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external nonReentrant {
        require(hosters.length == viewers.length && 
                viewers.length == contentHashes.length && 
                contentHashes.length == nonces.length && 
                nonces.length == signatures.length, "Array mismatch");

        uint256 available = waraToken.balanceOf(address(this));

        for (uint256 i = 0; i < hosters.length; i++) {
            if (!isSubscribed(viewers[i])) continue;

            bytes32 messageHash = keccak256(abi.encodePacked(hosters[i], viewers[i], contentHashes[i], nonces[i], block.chainid));
            bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
            
            if (processedSignatures[ethSignedMessageHash]) continue;
            
            address signer = ECDSA.recover(ethSignedMessageHash, signatures[i]);
            
            if (signer != viewers[i]) continue;

            processedSignatures[ethSignedMessageHash] = true;

            // Dynamic Payment Calculation
            uint256 payment = BASE_PAYMENT_PER_VIEW;
            if (available > POOL_HEALTH_THRESHOLD) {
                payment = MAX_PAYMENT_PER_VIEW;
            } else if (available > (POOL_HEALTH_THRESHOLD / 2)) {
                payment = (BASE_PAYMENT_PER_VIEW + MAX_PAYMENT_PER_VIEW) / 2;
            }

            if (available >= payment) {
                // Try-Catch transfer logic
                (bool success, bytes memory data) = address(waraToken).call(
                    abi.encodeWithSelector(IERC20.transfer.selector, hosters[i], payment)
                );
                
                if (success && (data.length == 0 || abi.decode(data, (bool)))) {
                    available -= payment;
                    totalPremiumViews++;
                    emit PremiumViewRecorded(hosters[i], viewers[i], payment);
                } else {
                    emit PaymentFailed(hosters[i], payment);
                }
            }
        }
    }

    /**
     * @notice Single record function with IMMEDIATE payment.
     */
    function recordPremiumView(
        address hoster, 
        address viewer, 
        bytes32 contentHash,
        uint256 nonce,
        bytes calldata signature
    ) external nonReentrant {
        require(isSubscribed(viewer), "User not subscribed");

        bytes32 messageHash = keccak256(abi.encodePacked(hoster, viewer, contentHash, nonce, block.chainid));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        
        require(!processedSignatures[ethSignedMessageHash], "Signature already processed");
        
        address signer = ECDSA.recover(ethSignedMessageHash, signature);
        require(signer == viewer, "Invalid signature from viewer");

        processedSignatures[ethSignedMessageHash] = true;

        uint256 available = waraToken.balanceOf(address(this));
        
        uint256 payment = BASE_PAYMENT_PER_VIEW;
        if (available > POOL_HEALTH_THRESHOLD) {
            payment = MAX_PAYMENT_PER_VIEW;
        } else if (available > (POOL_HEALTH_THRESHOLD / 2)) {
            payment = (BASE_PAYMENT_PER_VIEW + MAX_PAYMENT_PER_VIEW) / 2;
        }

        require(available >= payment, "Insufficient pool balance");
        
        totalPremiumViews++;
        require(waraToken.transfer(hoster, payment), "Payment failed");
        
        emit PremiumViewRecorded(hoster, viewer, payment);
    }

    // --- Helpers ---
    function isSubscribed(address user) public view returns (bool) {
        return subscriptions[user].expiresAt > block.timestamp;
    }

    function getCurrentPrice() public view returns (uint256) {
        int256 price = priceFeed.latestAnswer();
        require(price > 0, "Invalid price");
        uint256 waraPriceUSD = uint256(price); 
        return (MONTHLY_PRICE_USD * 1e8) / waraPriceUSD;
    }

    function getStats() external view returns (uint256, uint256, uint256, uint256, uint256) {
        uint256 available = waraToken.balanceOf(address(this));
        return (totalSubscribers, totalRevenue, available, totalPremiumViews, getCurrentPrice());
    }
}
