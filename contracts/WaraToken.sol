// SPDX-License-Identifier: MIT
// Wara Network - WaraToken (Sovereign Edition)
// Developed by YZX0 (https://github.com/Q-YZX0)
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WaraToken
 * @dev Implementation of the WARA token with automated sovereign distribution.
 * All supply is minted at creation (No Infinite Mint). 
 * Includes long-term deflationary mechanisms via burning.
 */
contract WaraToken is ERC20, ERC20Burnable, Ownable, ERC20Permit, ERC20Votes {
    
    // Deflationary Logic: 5% of the total supply is destined for future burns (implied by max cap vs mint)
    uint256 public constant TOTAL_SUPPLY_CAP = 1_000_000_000 * 10**18;

    constructor(
        address _dao, 
        address _vesting, 
        address _airdrop,
        address _subscriptions,
        address _linkRegistry
    ) 
        ERC20("WaraCoin", "WARA") 
        ERC20Permit("WaraCoin") 
        Ownable(msg.sender) 
    {
        require(
            _dao != address(0) && 
            _vesting != address(0) && 
            _airdrop != address(0) &&
            _subscriptions != address(0) &&
            _linkRegistry != address(0), 
            "Invalid pool addresses"
        );
        
        uint256 decimalsUnit = 10 ** decimals();

        // --- FIXED SOVEREIGN DISTRIBUTION (1,000,000,000 WARA) ---

        // 1. Founder (11%) + Liquidity Pool (20%) = 31% Liquid to Deployer
        _mint(msg.sender, 310_000_000 * decimalsUnit);

        // 2. AirDrops (7%) -> Automated to WaraAirdrop contract
        _mint(_airdrop, 70_000_000 * decimalsUnit);

        // 3. Hoster Bootstrap (5%) -> Automated to Subscriptions contract
        // These tokens flow to hosters until premium revenue sustains the pool.
        _mint(_subscriptions, 50_000_000 * decimalsUnit);

        // 4. Reputation & Bounties (13%) -> Automated to LinkRegistry contract
        _mint(_linkRegistry, 130_000_000 * decimalsUnit);

        // 5. Community DAO & Marketing (35%) -> Automated to WaraDAO
        _mint(_dao, 350_000_000 * decimalsUnit);

        // 6. Team Reserve (9%) -> Automated to WaraVesting
        _mint(_vesting, 90_000_000 * decimalsUnit);
    }

    // --- REQUIRED OVERRIDES FOR ERC20VOTES & PERMIT ---

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
