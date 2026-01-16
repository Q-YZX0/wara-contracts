# The Discovery Layer

This layer handles the registration of nodes and ensures they remain accessible to the network.

## NodeRegistry.sol
The central registry for all active WaraNodes.

-   **Node Identity**: Each node provides a "Technical Address" (`nodeSigner`) that uniquely identifies it.
-   **IP Tracking**: Stores the current public IP of each node, updated periodically by the Sentinel process.
-   **Security**: Only the node owner or the node itself can update its IP.
-   **Economies of Scale**: Manages the 1-year registration fee and redirects funds to the `GasPool`.

## GasPool.sol
A smart "Fuel Tank" for the network.

-   **Subsidies**: Holds ETH used to reimburse nodes for their operational gas costs.
-   **The Drip System**: Automatically refills a node's wallet when it performs a useful task (like updating its IP).
-   **Auth Management**: Only authorized contracts (Registry, LinkManager) can trigger refills, preventing pool draining.
