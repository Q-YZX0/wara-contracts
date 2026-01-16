# The Governance & Quality Layer

This layer ensures that content is trustable and that the network's catalog is community-driven.

## MediaRegistry.sol
The decentralized database of movies and series.

-   **DAO Proposals**: Users propose new titles for the official catalog.
-   **Voting Period**: Token holders vote (Yes/No) to verify the metadata and existence of the media.
-   **Execution**: Once a proposal is resolved, the title becomes an "Official Wara Title".

## LinkRegistry.sol
Connects media titles to actual P2P streaming links.

-   **Link Casting**: Hosters register their content hashes and IPs to specific media IDs.
-   **Reputation (Trust Score)**: Users vote on links. High Trust Score links are displayed first.
-   **Gas Integration**: Registering a high-quality link triggers a gas refill for the hoster from the `GasPool`.

## LeaderBoard.sol
Tracks the performance and reliability of all hosters.

-   **Points**: Earned by serving content, receiving upvotes, and maintaining uptime.
-   **Visibility**: Top nodes are promoted in the network, leading to more traffic and higher revenue.
