// SPDX-License-Identifier: MIT
// Wara Network - NodeRegistry
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

/**
 * @title NodeRegistry
 * @notice Registro descentralizado de nodos Wara para 
 * @dev Los nodos pagan una pequeña fee para registrarse y aparecer en la red
 */
contract NodeRegistry {
    struct Node {
        string name;            // Nombre único (ej: "salsa")
        address operator;       // Wallet del dueño (recibe dinero)
        address nodeAddress;    // Wallet del servidor (firma el Gossip)
        uint256 registeredAt;
        uint256 expiresAt;      // Registro expira después de X días
        bool active;
        string currentIP;       // Sentinel IP
        uint256 lastIPUpdate;   // Timestamp of last IP update
        bool hasQualityRPC;     // Voluntary sentinel (has quality RPC access)
    }

    // Mapping de nameHash => Node
    mapping(bytes32 => Node) public nodes;
    
    // Mapping para reverse lookup (Node Address -> Name Hash)
    mapping(address => bytes32) public nodeAddressToNameHash;

    // Mapping para reverse lookup
    mapping(string => bool) public nameExists;
    
    // Array de nombres activos
    bytes32[] public activeNodeHashes;
    
    // Fee de registro
    uint256 public registrationFee = 0.001 ether;
    uint256 public registrationDuration = 365 days;
    
    address public owner;
    address public gasPool;
    
    event NodeRegistered(string name, address indexed operator, address indexed nodeAddress, uint256 expiresAt);
    event NodeRenewed(string name, uint256 newExpiresAt);
    event NodeDeactivated(string name);
    event IPUpdated(string indexed name, string newIP);
    event QualityRPCUpdated(address indexed nodeAddress, bool enabled);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @notice Registra un nombre de nodo con una identidad delegada
     * @param name Nombre deseado
     * @param nodeAddress Dirección pública de la llave del servidor
     */
    function registerNode(string calldata name, address nodeAddress) external payable {
        require(msg.value >= registrationFee, "Insufficient fee");
        require(bytes(name).length >= 3, "Name too short");
        require(!nameExists[name], "Name already taken");
        require(nodeAddress != address(0), "Invalid node address");
        
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        
        Node storage node = nodes[nameHash];
        node.name = name;
        node.operator = msg.sender;
        node.nodeAddress = nodeAddress;
        node.registeredAt = block.timestamp;
        node.expiresAt = block.timestamp + registrationDuration;
        node.active = true;
        node.lastIPUpdate = block.timestamp;
        
        nameExists[name] = true;
        activeNodeHashes.push(nameHash);
        nodeAddressToNameHash[nodeAddress] = nameHash;
        
        // Sentinel Funding Logic: Send 10% to the Node Wallet for initial buffer
        // The remaining 90% stays in the GasPool to be dripped via updateIP calls
        uint256 nodeShare = (msg.value * 10) / 100;
        uint256 ownerShare = (msg.value * 5) / 100;
        uint256 poolShare = msg.value - nodeShare - ownerShare;

        payable(nodeAddress).transfer(nodeShare);
        payable(owner).transfer(ownerShare);

        if (gasPool != address(0) && poolShare > 0) {
            (bool success, ) = payable(gasPool).call{value: poolShare}("");
            success;
        }

        emit NodeRegistered(name, msg.sender, nodeAddress, node.expiresAt);
    }
    
    function renewNode(string calldata name) external payable {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        Node storage node = nodes[nameHash];
        require(node.operator == msg.sender, "Not node operator");
        require(msg.value >= registrationFee, "Insufficient fee");
        
        node.expiresAt = block.timestamp + registrationDuration;
        node.active = true;
        
        // Renewal Funding Logic: 10/5/85 Split
        uint256 nodeShare = (msg.value * 10) / 100;
        uint256 ownerShare = (msg.value * 5) / 100;
        uint256 poolShare = msg.value - nodeShare - ownerShare;

        payable(node.nodeAddress).transfer(nodeShare);
        payable(owner).transfer(ownerShare);

        if (gasPool != address(0) && poolShare > 0) {
            (bool success, ) = payable(gasPool).call{value: poolShare}("");
            success;
        }

        emit NodeRenewed(name, node.expiresAt);
    }
    
    function updateIP(string calldata newIP) external {
        bytes32 nameHash = nodeAddressToNameHash[msg.sender];
        Node storage node = nodes[nameHash];
        
        require(node.active, "Node not found or inactive");
        require(msg.sender == node.nodeAddress || msg.sender == node.operator, "Unauthorized");
        require(block.timestamp < node.expiresAt, "Subscription expired");

        node.currentIP = newIP;
        node.lastIPUpdate = block.timestamp;

        // Auto-Refill Gas from Pool (Drip system)
        if (gasPool != address(0)) {
            // Refill 0.001 ETH for IP maintenance (approx 50k gas at 20 gwei)
            (bool success, ) = gasPool.call(abi.encodeWithSignature("refillGas(address,uint256)", node.nodeAddress, 0.001 ether));
            success;
            // We ignore failure (e.g. cooldown or empty pool)
        }

        emit IPUpdated(node.name, newIP);
    }

    function releaseNode(string calldata name) external {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        Node storage node = nodes[nameHash];
        require(node.operator == msg.sender, "Not node operator");
        node.active = false;
        emit NodeDeactivated(name);
    }
    
    function getNode(string calldata name) external view returns (
        address operator,
        address nodeAddress,
        uint256 expiresAt,
        bool active,
        string memory currentIP
    ) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        Node storage node = nodes[nameHash];
        return (
            node.operator,
            node.nodeAddress,
            node.expiresAt,
            node.active && node.expiresAt > block.timestamp,
            node.currentIP
        );
    }
    
    function getActiveNodeCount() external view returns (uint256) {
        return activeNodeHashes.length;
    }

    function getBootstrapNodes(uint256 limit) external view returns (string[] memory names, string[] memory ips) {
        uint256 total = activeNodeHashes.length;
        if (limit > total) limit = total;
        
        names = new string[](limit);
        ips = new string[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            // Get from end (newest)
            bytes32 hash = activeNodeHashes[total - 1 - i];
            Node storage n = nodes[hash];
            names[i] = n.name;
            ips[i] = n.currentIP;
        }
    }
    
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        registrationFee = newFee;
    }
    
    function setGasPool(address _gasPool) external onlyOwner {
        gasPool = _gasPool;
    }

    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    /**
     * @notice Enable/disable quality RPC status (Sentinel)
     * @param enabled True to become a Sentinel, false to opt-out
     */
    function setQualityRPC(bool enabled) external {
        bytes32 nameHash = nodeAddressToNameHash[msg.sender];
        
        // Allow both operator and nodeAddress to set this
        if (nameHash == bytes32(0)) {
            // Try reverse lookup by operator
            revert("Node not found");
        }
        
        Node storage node = nodes[nameHash];
        require(node.active, "Node not active");
        require(msg.sender == node.operator || msg.sender == node.nodeAddress, "Unauthorized");
        
        node.hasQualityRPC = enabled;
        emit QualityRPCUpdated(node.nodeAddress, enabled);
    }
}
