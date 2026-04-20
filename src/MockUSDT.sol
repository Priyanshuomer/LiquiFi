// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDT
 * @notice Mock USDT token for local and testnet deployment of PoolForge.
 * @dev Mints a large supply to the deployer on construction.
 *      Use transferMockTokens() to distribute to test accounts.
 */
contract MockUSDT is ERC20 {

    address public s_owner;

    error MockUSDT__OnlyOwner();

    constructor() ERC20("Mock USDT", "mUSDT") {
        s_owner = msg.sender;
        // Mint 10,000,000 mUSDT to deployer (6 decimals like real USDT)
        _mint(msg.sender, 10_000_000 * 10 ** decimals());
    }

    /// @notice Override decimals to match real USDT (6 instead of ERC20 default 18)
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Distributes mock tokens to test accounts
     * @param to      Recipient address
     * @param amount  Amount in USDT units (e.g. 1000 = 1000 mUSDT)
     */
    function transferMockTokens(address to, uint256 amount) public {
        if (msg.sender != s_owner) revert MockUSDT__OnlyOwner();
        _transfer(s_owner, to, amount * 10 ** decimals());
    }

    /**
     * @notice Anyone can mint for testing — remove in production
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount * 10 ** decimals());
    }
}