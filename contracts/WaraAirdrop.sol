// SPDX-License-Identifier: MIT
// Wara Network - WaraAirdrop (Autonomous Edition)
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title WaraAirdrop
 * @dev Autonomous Airdrop system that allows users to register and triggers 
 * random distribution cycles every 30 days.
 */
contract WaraAirdrop is Ownable {
    IERC20 public waraToken;
    
    struct AirdropCycle {
        bytes32 merkleRoot;
        uint256 totalAmount;
        uint256 startTime;
        bool active;
    }

    // Airdrop Settings
    uint256 public constant CYCLE_COOLDOWN = 30 days;
    uint256 public constant REWARD_PER_USER = 100 * 10**18; // 100 WARA fixed for example
    
    mapping(uint256 => AirdropCycle) public cycles;
    uint256 public currentCycleId;
    uint256 public lastCycleTime;

    // Registration List (Users who want to participate)
    address[] public registeredUsers;
    mapping(address => bool) public isRegistered;
    
    // Claim tracking per cycle: cycleId => user => claimed
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    event UserRegistered(address indexed user);
    event CycleStarted(uint256 indexed cycleId, bytes32 merkleRoot, uint256 participants);
    event TokensClaimed(uint256 indexed cycleId, address indexed user, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function setToken(address _token) external onlyOwner {
        require(address(waraToken) == address(0), "Token already set");
        waraToken = IERC20(_token);
    }

    /**
     * @notice Users sign up to be eligible for future airdrops
     */
    function register() external {
        require(!isRegistered[msg.sender], "Already registered");
        registeredUsers.push(msg.sender);
        isRegistered[msg.sender] = true;
        emit UserRegistered(msg.sender);
    }

    /**
     * @notice Admin activates a new cycle with a Merkle Root 
     * @dev Root should be generated off-chain using a subset of registeredUsers
     */
    function startNewCycle(bytes32 _merkleRoot) external onlyOwner {
        require(block.timestamp >= lastCycleTime + CYCLE_COOLDOWN, "Wait for cooldown");
        
        currentCycleId++;
        cycles[currentCycleId] = AirdropCycle({
            merkleRoot: _merkleRoot,
            totalAmount: 0, // Calculated during claims
            startTime: block.timestamp,
            active: true
        });
        
        lastCycleTime = block.timestamp;
        emit CycleStarted(currentCycleId, _merkleRoot, registeredUsers.length);
    }

    /**
     * @notice Claim from a specific cycle
     */
    function claim(uint256 cycleId, uint256 amount, bytes32[] calldata merkleProof) external {
        AirdropCycle storage cycle = cycles[cycleId];
        require(cycle.active, "Cycle not active");
        require(!hasClaimed[cycleId][msg.sender], "Already claimed this cycle");

        bytes32 node = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, cycle.merkleRoot, node), "Invalid proof");

        hasClaimed[cycleId][msg.sender] = true;
        require(waraToken.transfer(msg.sender, amount), "Transfer failed");

        emit TokensClaimed(cycleId, msg.sender, amount);
    }

    /**
     * @notice Helper to get all registered users for off-chain root generation
     */
    function getRegisteredUsers() external view returns (address[] memory) {
        return registeredUsers;
    }
    
    function totalRegistered() external view returns (uint256) {
        return registeredUsers.length;
    }

    function recoverERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
