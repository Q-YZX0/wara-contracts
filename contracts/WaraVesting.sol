// SPDX-License-Identifier: MIT
// Wara Network - Team Vesting Vault
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WaraTeamVesting
 * @dev Holds the 9% Team supply and releases it linearly over 12 months.
 * This separation ensures the WaraToken remains simple and auditable.
 */
contract WaraVesting is Ownable {
    
    IERC20 public waraToken;
    uint256 public constant TOTAL_TEAM_RESERVE = 90_000_000 * 10**18;
    uint256 public claimed;
    uint256 public immutable startTime;
    uint256 public constant DURATION = 365 days;

    event TokensClaimed(address indexed beneficiary, uint256 amount);

    constructor(address _owner) Ownable(_owner) {
        startTime = block.timestamp;
    }

    /**
     * @dev Link the token after deployment to start the vesting tracking.
     */
    function setToken(address _token) external onlyOwner {
        require(address(waraToken) == address(0), "Token already set");
        waraToken = IERC20(_token);
    }

    /**
     * @notice Checks how many tokens are currently available to claim.
     */
    function getAvailableAmount() public view returns (uint256) {
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 releasable = elapsedTime >= DURATION ? 
            TOTAL_TEAM_RESERVE : (TOTAL_TEAM_RESERVE * elapsedTime) / DURATION;
        
        return releasable - claimed;
    }

    /**
     * @notice Transfers available vested tokens to the owner.
     */
    function claim() external onlyOwner {
        uint256 amount = getAvailableAmount();
        require(amount > 0, "No tokens available for claim yet");
        
        claimed += amount;
        require(waraToken.transfer(owner(), amount), "Transfer failed");
        
        emit TokensClaimed(owner(), amount);
    }
}
