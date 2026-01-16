# The Economy Layer

This layer manages the flow of value between advertisers, users, and content hosters using the $WARA token.

## WaraToken.sol (WARA)
The native utility token of the Wara network.

-   **ERC20 Standard**: Used for all payments, rewards, and governance.
-   **Stable Pricing**: Contract logic ensures that services (ads, subs) are priced in USD but settled in WARA.

## AdManager.sol
Connects advertisers with the node network.

-   **Campaign Creation**: Advertisers deposit WARA to buy "Views".
-   **Guaranteed Duration**: Pricing is based on the ad's length (e.g., $0.01 per second).
-   **Proof of View**: rewards content hosters only when a valid, signed message from the viewer is presented.
-   **Community Moderation**: If enough users report an ad as malicious, it is automatically paused.

## Subscriptions.sol
Manages the premium viewing experience.

-   **Monthly Plans**: Fixed USD price (e.g., $5) paid in WARA.
-   **Incentive Pool**: 70% of subscription revenue is held in a pool to reward hosters who serve high-quality content to premium users.
-   **Privacy**: Uses gasless digital signatures from subscribers to authorize hoster payouts without exposing user data on-chain.
