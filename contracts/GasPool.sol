// SPDX-License-Identifier: MIT
// Wara Network - GasPool
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GasPool
 * @notice A system pool that holds native currency to subsidize gas for active nodes.
 */
contract GasPool is Ownable {
    
    // Contracts authorized to request gas refills (e.g., LinkReputation)
    mapping(address => bool) public authorizedManagers;
    
    // Limits to prevent draining the pool
    uint256 public maxRefillAmount = 0.05 ether; // Max gas per request
    uint256 public refillCooldown = 1 hours;
    mapping(address => uint256) public lastRefill;

    event GasRefilled(address indexed recipient, uint256 amount);
    event ManagerStatusChanged(address indexed manager, bool authorized);
    event FundsReceived(address indexed sender, uint256 amount);

    constructor() Ownable(msg.sender) {}

    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    modifier onlyAuthorized() {
        require(authorizedManagers[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    function setManagerStatus(address manager, bool status) external onlyOwner {
        authorizedManagers[manager] = status;
        emit ManagerStatusChanged(manager, status);
    }

    function setLimits(uint256 _maxAmount, uint256 _cooldown) external onlyOwner {
        maxRefillAmount = _maxAmount;
        refillCooldown = _cooldown;
    }

    /**
     * @notice Send native currency to a node to cover gas costs
     * @param recipient The node address to refill
     * @param amount Amount in wei
     */
    function refillGas(address recipient, uint256 amount) external onlyAuthorized {
        require(amount <= maxRefillAmount, "Amount exceeds limit");
        require(block.timestamp >= lastRefill[recipient] + refillCooldown, "Cooldown active");
        require(address(this).balance >= amount, "Insufficient pool balance");

        lastRefill[recipient] = block.timestamp;
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Transfer failed");

        emit GasRefilled(recipient, amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }
}
