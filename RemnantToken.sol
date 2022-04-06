// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RemnantToken is ERC20, Ownable {
    bool public bp; // Bot protection that can be toggled on/off until permanently disabled
    bool public bpPermanentlyDisabled; // Starts false, but when set to true, is permanently true
    uint public bpMaxGas; // Max gwei per trade allowed during bot protection
    uint public bpMaxTokenTradeValue; // Max number of tokens an address can trade during bot protection
    bool public bpTradingEnabled; // Enables trading during bot protection period
    mapping (address => bool) private bpWhitelisted; // Mapped boolean if router whitelisted
    mapping (address => bool) private bpAddressAlreadyTransacted; // Mapped boolean if traded already

    constructor() ERC20("Remnant", "REMN") {
        _mint(msg.sender, 10000000000 * 10 ** decimals()); // Mint 10,000,000,000 tokens

        bpWhitelisted[0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D] = true; // UNISWAP V2 ROUTER MAINNET
        bpWhitelisted[0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff] = true; // QUICKSWAP ROUTER POLYGON
        bpWhitelisted[0x10ED43C718714eb63d5aA57B78B54704E256024E] = true; // PANCAKESWAP ROUTER BSC
        bpWhitelisted[0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F] = true; // SUSHISWAP ROUTER MAINNET

        bpMaxGas = 501 * 10 ** decimals(); // 501 gwei max on bot protection by default, adjustable
        bpMaxTokenTradeValue = 10000000 * 10 ** decimals(); // 10,000,000 tokens is the max an address can trade during bot protection
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Adds a new whitelist address to the bot protection (for swap routers).
     */
    function addNewWhitelistBp(address whitelistAddress) public onlyOwner {
        bpWhitelisted[whitelistAddress] = true;
    }

    /**
     * @dev Toggles bot protection, blocking suspicious transactions during liquidity events.
     */
    function toggleBp() public onlyOwner {
        bp = !bp;
    }

    /**
     * @dev Sets max gwei allowed in transaction when bot protection is on.
     */
    function setMaxGweiBp(uint gweiAmount) public onlyOwner {
        bpMaxGas = gweiAmount;
    }

    /**
     * @dev Sets max trade value allowed in transaction when bot protection is on.
     */
    function setMaxTradeValue(uint val) public onlyOwner {
        bpMaxTokenTradeValue = val;
    }

    /**
     * @dev Turns off bot protection permanently.
     */
    function disableBpPermanent() public onlyOwner {
        bp = false;
        bpPermanentlyDisabled = true;
    }

    /**
     * @dev Toggles trading (requires bp not permanently disabled)
     */
    function toggleTrading() public onlyOwner {
        require(!bpPermanentlyDisabled, "Cannot toggle trading when bot protection already disabled permanently");
        bpTradingEnabled = !bpTradingEnabled;
    }

    /**
     * @dev Check before token transfer if bot protection is on, to block suspicious transactions
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (bp && !bpPermanentlyDisabled && msg.sender != owner()) {
            require(bpWhitelisted[msg.sender] == true); // Only swap router calls are allowed, msg.sender is theoretically the swap router
            require(bpAddressAlreadyTransacted[tx.origin] == false); // Only 1 trade per address in first XX minutes of swap liquidity (tx.origin cannot be a contract so is theoretically the user address)
            require(tx.gasprice <= bpMaxGas); // Max gwei limit on transaction
            require(bpTradingEnabled); // Trading bool must be set on
            require(amount <= bpMaxTokenTradeValue); // Must trade less than or equal to specified max trade value
            
            bpAddressAlreadyTransacted[tx.origin] = true; // User has now transacted so add to mapping (to limit user to 1 trade)
        }

        super._beforeTokenTransfer(from, to, amount);
    }

}
