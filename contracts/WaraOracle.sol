// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./NodeRegistry.sol";

interface ILinkRegistry {
    function payOracleReward(address judge, uint256 amount) external;
}

contract WaraOracle {
    using ECDSA for bytes32;

    NodeRegistry public immutable nodeRegistry;
    address public linkRegistry; // The pool that pays WARA
    address public gasPool; // The pool that pays ETH
    
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint8 public constant decimals = 8;
    string public description = "WARA / USD - Jury & Judge System";

    uint256 public juryPercentage = 20; 
    uint256 public baseReward = 0.5 * 10**18; // 0.5 WARA starting reward
    uint256 public floorReward = 0.2 * 10**18; // 0.2 WARA minimum reward

    event PriceUpdated(int256 price, uint256 timestamp, address indexed judge);
    event GasRefunded(address indexed judge, uint256 amount);

    constructor(address _nodeRegistry, int256 _initialPrice) {
        nodeRegistry = NodeRegistry(_nodeRegistry);
        latestAnswer = _initialPrice;
        latestTimestamp = block.timestamp;
    }

    function submitPrice(
        int256 _price, 
        uint256 _timestamp, 
        bytes[] calldata _signatures
    ) external {
        uint256 startGas = gasleft();
        require(_timestamp > latestTimestamp, "Old data");
        require(_timestamp <= block.timestamp + 5 minutes, "Future data");

        uint256 totalNodes = nodeRegistry.getActiveNodeCount();
        require(totalNodes > 0, "No nodes");

        bytes32 jurySeed = blockhash(block.number - 1);
        if (jurySeed == bytes32(0)) jurySeed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao));

        bytes32 messageHash = keccak256(abi.encodePacked(_price, _timestamp, block.chainid));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        
        string[] memory seenIPs = new string[](_signatures.length);
        address[] memory seenOperators = new address[](_signatures.length);
        uint256 validVotes = 0;

        for (uint256 i = 0; i < _signatures.length; i++) {
            address signer = ethSignedMessageHash.recover(_signatures[i]);
            bytes32 nameHash = nodeRegistry.nodeAddressToNameHash(signer);
            if (nameHash == bytes32(0)) continue; 
            
            (string memory name,,,,,,) = nodeRegistry.nodes(nameHash);
            (address operator,, uint256 expiresAt, bool active, string memory currentIP) = nodeRegistry.getNode(name);
            if (!active || expiresAt <= block.timestamp) continue;

            // LOTTERY RULE:
            uint256 selectionChance = uint256(keccak256(abi.encodePacked(jurySeed, nameHash))) % 100;
            // RULE: If we have very few nodes, the lottery might block everyone.
            // We allow the first 'min' signatures to bypass the lottery IF totalNodes is small.
            uint256 required = (totalNodes * juryPercentage) / 100;
            if (required < 3) required = 3;

            if (selectionChance >= juryPercentage && validVotes >= required) continue;

            bool isSybil = false;
            for(uint256 j = 0; j < validVotes; j++) {
                if (keccak256(abi.encodePacked(seenIPs[j])) == keccak256(abi.encodePacked(currentIP)) || seenOperators[j] == operator) {
                    isSybil = true;
                    break;
                }
            }
            if (!isSybil) {
                seenIPs[validVotes] = currentIP;
                seenOperators[validVotes] = operator;
                validVotes++;
            }
        }

        uint256 finalRequired = (totalNodes * juryPercentage) / 100;
        if (finalRequired < 3) finalRequired = 3;
        require(validVotes >= finalRequired, "Not enough unique jury signatures");

        latestAnswer = _price;
        latestTimestamp = _timestamp;
        // 1. WARA Reward (vía LinkRegistry) - Sent to the HUMAN OPERATOR
        if (linkRegistry != address(0)) {
            bytes32 judgeNameHash = nodeRegistry.nodeAddressToNameHash(msg.sender);
            (string memory judgeName,,,,,,) = nodeRegistry.nodes(judgeNameHash);
            (address judgeOperator,,,,) = nodeRegistry.getNode(judgeName);
            
            uint256 reward = getDynamicReward(totalNodes);
            if (judgeOperator != address(0)) {
                try ILinkRegistry(linkRegistry).payOracleReward(judgeOperator, reward) {} catch {}
            }
        }

        // 2. ETH Refund (vía GasPool) - Sent to the TECH WALLET (msg.sender)
        uint256 gasUsed = (startGas - gasleft() + 65000); 
        uint256 txFee = gasUsed * tx.gasprice;
        if (gasPool != address(0)) {
            (bool success, ) = gasPool.call(abi.encodeWithSignature("refillGas(address,uint256)", msg.sender, txFee));
            success;
            if (success) emit GasRefunded(msg.sender, txFee);
        }

        emit PriceUpdated(_price, _timestamp, msg.sender);
    }

    /**
     * @notice Calculate reward based on network size
     * @param totalNodes Current active nodes
     */
    function getDynamicReward(uint256 totalNodes) public view returns (uint256) {
        if (totalNodes <= 5) return baseReward;
        
        // Decrease reward as network grows to prevent exploitation
        // Decay: -0.001 WARA per additional node after 5
        uint256 deduction = (totalNodes - 5) * 1e15; 
        
        if (deduction >= (baseReward - floorReward)) {
            return floorReward;
        }
        return baseReward - deduction;
    }

    function setParams(uint256 _percent, uint256 _baseReward, uint256 _floorReward, address _gasPool, address _linkRegistry) external {
        require(msg.sender == nodeRegistry.owner());
        juryPercentage = _percent;
        baseReward = _baseReward;
        floorReward = _floorReward;
        gasPool = _gasPool;
        linkRegistry = _linkRegistry;
    }
}
