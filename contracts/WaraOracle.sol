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

    struct JudgeInfo {
        address nodeAddress;
        string name;
        string ip;
        uint256 rank;
    }

    event PriceUpdated(int256 price, uint256 timestamp, address indexed judge);
    event GasRefunded(address indexed judge, uint256 amount);

    constructor(address _nodeRegistry, int256 _initialPrice) {
        nodeRegistry = NodeRegistry(_nodeRegistry);
        latestAnswer = _initialPrice;
        latestTimestamp = block.timestamp;
    }

    /**
     * @notice Returns the 10 elected judges for the current cycle based on recent activity.
     */
    function getElectedJudges() public view returns (JudgeInfo[10] memory elected) {
        uint256 total = nodeRegistry.getActiveNodeCount();
        if (total == 0) return elected;

        // Use a cycle-based seed (changes every 10 minutes)
        uint256 cycleId = block.timestamp / 10 minutes;
        bytes32 seed = keccak256(abi.encodePacked(cycleId, address(nodeRegistry)));
        
        uint256 found = 0;
        uint256 startIndex = uint256(seed) % total;
        
        // Iterate to find 10 warm nodes (updated IP in the last 24 hours)
        // Cap search at 50 to prevent Gas Limit DoS
        for (uint256 i = 0; i < total && found < 10 && i < 50; i++) {
            uint256 idx = (startIndex + i) % total;
            bytes32 nameHash = nodeRegistry.activeNodeHashes(idx);
            
            (string memory name, , address nodeAddress, ,uint256 expiresAt, bool active, string memory currentIP, uint256 lastUpdate,) = nodeRegistry.nodes(nameHash);
            
            // Criteria: Active, not expired, and updated within last 24h
            if (active && expiresAt > block.timestamp && (block.timestamp - lastUpdate) < 24 hours) {
                elected[found] = JudgeInfo({
                    nodeAddress: nodeAddress,
                    name: name,
                    ip: currentIP,
                    rank: found
                });
                found++;
            }
        }
    }

    /**
     * @notice Returns the list of jury members selected by lottery for the current cycle
     * @dev Uses the same lottery logic as submitPrice to determine valid jury members
     * @return juryAddresses Array of node addresses selected as jury
     * @return juryIPs Array of IP addresses corresponding to jury members
     * @return juryNames Array of node names corresponding to jury members
     */
    function getElectedJury() public view returns (
        address[] memory juryAddresses, 
        string[] memory juryIPs,
        string[] memory juryNames
    ) {
        uint256 total = nodeRegistry.getActiveNodeCount();
        if (total == 0) {
            return (new address[](0), new string[](0), new string[](0));
        }

        // Use same seed as submitPrice would use
        bytes32 jurySeed = blockhash(block.number - 1);
        if (jurySeed == bytes32(0)) {
            jurySeed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao));
        }

        // Calculate how many jury members we need (20% of total, minimum 3)
        uint256 required = (total * juryPercentage) / 100;
        if (required < 3) required = 3;

        // Temporary arrays (max size = total nodes)
        address[] memory tempAddresses = new address[](total);
        string[] memory tempIPs = new string[](total);
        string[] memory tempNames = new string[](total);
        uint256 count = 0;

        // Iterate through all active nodes and select based on lottery
        for (uint256 i = 0; i < total; i++) {
            bytes32 nameHash = nodeRegistry.activeNodeHashes(i);
            
            (
                string memory name,
                ,
                address nodeAddress,
                ,
                uint256 expiresAt,
                bool active,
                string memory currentIP,
                ,
            ) = nodeRegistry.nodes(nameHash);

            // Skip inactive or expired nodes
            if (!active || expiresAt <= block.timestamp) continue;

            // Apply lottery rule
            if (_isSelectedByLottery(jurySeed, nameHash)) {
                tempAddresses[count] = nodeAddress;
                tempIPs[count] = currentIP;
                tempNames[count] = name;
                count++;
            }
        }

        // Resize arrays to actual count
        juryAddresses = new address[](count);
        juryIPs = new string[](count);
        juryNames = new string[](count);
        
        for (uint256 i = 0; i < count; i++) {
            juryAddresses[i] = tempAddresses[i];
            juryIPs[i] = tempIPs[i];
            juryNames[i] = tempNames[i];
        }
    }
    
    function _isSelectedByLottery(bytes32 seed, bytes32 nameHash) internal view returns (bool) {
        return (uint256(keccak256(abi.encodePacked(seed, nameHash))) % 100) < juryPercentage;
    }


    function submitPrice(
        int256 _price, 
        uint256 _timestamp, 
        bytes[] calldata _signatures
    ) external {
        uint256 startGas = gasleft();
        require(_timestamp > latestTimestamp, "Old data");
        require(_timestamp <= block.timestamp + 5 minutes, "Future data");

        // --- ELECTED JUDGE & TIME-SLOT VALIDATION ---
        JudgeInfo[10] memory electedWorkforce = getElectedJudges();
        bool isElected = false;
        uint256 myRank = 0;
        
        for (uint256 i = 0; i < 10; i++) {
            if (electedWorkforce[i].nodeAddress == msg.sender) {
                isElected = true;
                myRank = i;
                break;
            }
        }
        require(isElected, "Not an elected Judge for this cycle");

        // Window logic: 1 minute per rank
        uint256 cycleStartTime = (block.timestamp / 10 minutes) * 10 minutes;
        require(block.timestamp >= cycleStartTime + (myRank * 1 minutes), "It is not your turn yet");

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
            
            (, address operator, , , uint256 expiresAt, bool active, string memory currentIP, ,) = nodeRegistry.nodes(nameHash);
            if (!active || expiresAt <= block.timestamp) continue;

            // LOTTERY RULE:
            uint256 required = (totalNodes * juryPercentage) / 100;
            if (required < 3) required = 3;

            // If NOT selected by lottery AND we already have enough votes, skip.
            // (Allows non-jury members ONLY if we are desperate/below required)
            if (!_isSelectedByLottery(jurySeed, nameHash) && validVotes >= required) continue;

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
            (, address judgeOperator, , , , , , ,) = nodeRegistry.nodes(judgeNameHash);
            
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
            (success); 
            if (success) emit GasRefunded(msg.sender, txFee);
        }

        emit PriceUpdated(_price, _timestamp, msg.sender);
    }

    /**
     * @notice Calculate reward based on network size
     */
    function getDynamicReward(uint256 totalNodes) public view returns (uint256) {
        if (totalNodes <= 5) return baseReward;
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

    /**
     * @notice Recover stuck ERC20 tokens
     */
    function recoverERC20(address token, uint256 amount) external {
        require(msg.sender == nodeRegistry.owner(), "Only owner");
        // IERC20 interface is needed, assume it's available or use low-level call
        (bool success, ) = token.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount));
        require(success, "Transfer failed");
    }
}
