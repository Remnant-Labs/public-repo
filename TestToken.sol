// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RTestToken is ERC20, Ownable {
    bool public bp; // Bot protection
    bool public bpPermanentlyDisabled;
    uint public bpMaxGas; // Max gwei per trade allowed during bot protection
    uint public bpMaxTokenTradeValue; // Max number of tokens an address can trade during bot protection
    bool public bpTradingEnabled; // Enables trading during bot protection period
    address[] public bpWhitelisted; // Whitelist addresses (swap liquidity routers)
    address[] public bpAddresses; // Array of addresses that transacted during bot protection (only 1 transaction allowed per address)
    mapping (address => boolean) private bpAddressTransacted; // Mapped boolean if traded already

    constructor() ERC20("RTestToken", "RTT") {
        _mint(msg.sender, 1000000 * 10 ** decimals()); // Mint 1,000,000 tokens

        bpWhitelisted[0] = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // UNISWAP V2 ROUTER MAINNET
        bpWhitelisted[1] = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; // QUICKSWAP ROUTER POLYGON
        bpWhitelisted[2] = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PANCAKESWAP ROUTER BSC
        bpWhitelisted[3] = 0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f; // SUSHISWAP ROUTER MAINNET

        bpMaxGas = 501 * 10 ** decimals(); // 501 gwei max on bot protection by default, adjustable
        bpMaxTokenTradeValue = 10000 * 10 ** decimals(); // 10,000 tokens is the max an address can trade during bot protection
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Adds a new whitelist address to the bot protection (for swap routers).
     */
    function addNewWhitelistBp(address whitelistAddress) public onlyOwner {
        bpWhitelisted.push(whitelistAddress);
    }

    /**
     * @dev Toggles bot protection, blocking suspicious transactions during liquidity events.
     */
    function toggleBp(bool enabled) public onlyOwner {
        bp = !bp;
    }

    /**
     * @dev Sets max gwei allowed in transaction when bot protection is on.
     */
    function setMaxGweiBp(uint gwei) public onlyOwner {
        bpMaxGas = gwei;
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
        require(!bpPermanentlyDisabled, "Bot protection permanently disabled");
        bp = false;
        bpPermanentlyDisabled = true;
    }

    /**
     * @dev Turns on trading permanently (owner should call shortly after providing liquidity to swaps)
     */
    function enableTradingPermanent() public onlyOwner {
        require(!bpTradingEnabled, "Trading enabled during bot protection");
        bpTradingEnabled = true;
    }

    /**
     * @dev Check that it is the first time this address is transacting
     */
    function bpFirstTimeTransacting(address trader) internal {
        if (bpAddressTransacted[trader]) {
            return false
        } else {
            bpAddressesTransacted.push(trader);
            return true
        }
        return true
    }

    /**
     * @dev Check before token transfer if bot protection is on, to block suspicious transactions
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (bp && !bpPermanentlyDisabled && msg.sender != owner()) {
            require(transactorIsWhitelisted(msg.sender)); // Only swap routers
            require(bpFirstTimeTransacting(msg.sender)); // Only 1 trade in first xx minutes of liquidity provision
            require(tx.gasprice <= bpMaxGas); // Max gwei limi
            require(bpTradingEnabled); // Trading must be set on
            require(amount <= bpMaxTokenTradeValue); // Must trade less than or equal to specified max trade value
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Whitelist the swap routers during bot protection, so swap is still available
     */
    function transactorIsWhitelisted(address transactor) internal {
        for (uint i=0; i<bpWhitelisted.length; i++) {
            if (transactor == bpWhitelisted[i]) {
                return true
            }
        }
        return false
    }
    

}
