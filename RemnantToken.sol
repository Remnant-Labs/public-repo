// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error SwapNotEnabledYet();

contract RemnantToken is ERC20, Ownable {

    // For team, staking, P2E ecosystem, other
    uint256 public constant INITIAL_AMOUNT_TEAM = 1_000_000_000; // 10%
    uint256 public constant INITIAL_AMOUNT_STAKING = 1_500_000_000; // 15%
    uint256 public constant INITIAL_AMOUNT_ECOSYSTEM = 2_500_000_000; // 25%
    uint256 public constant INITIAL_AMOUNT_OTHER = 5_000_000_000; // 50%
    
    address public constant ADDRESS_TEAM = 0xb09613A3e92971Db7a038BC5cDDd635Bd718cAC1;
    address public constant ADDRESS_STAKING = 0x5ecd185e32b478B4f58C5F3565FdceA3023884A1;
    address public constant ADDRESS_ECOSYSTEM = 0x331cEE12D7f2D86Bd971b03B1CF5621D54c5Bf88;
    address public constant ADDRESS_OTHER = 0x72b082925f7e51B1Acfd34425846913Be6B043B7;
    
    // For bp (bot protection), to deter liquidity sniping, enabled during first moments of each swap liquidity (ie. Uniswap, Quickswap, etc)
    uint256 public bpAllowedNumberOfTx;     // Max allowed number of buys/sells on swap during bp per address
    uint256 public bpMaxGas;                // Max gwei per trade allowed during bot protection
    uint256 public bpMaxBuyAmount;          // Max number of tokens an address can buy during bot protection
    uint256 public bpMaxSellAmount;         // Max number of tokens an address can sell during bot protection
    bool public bpEnabled;                  // Bot protection, on or off
    bool public bpTradingEnabled;           // Enables trading during bot protection period
    bool public bpPermanentlyDisabled;      // Starts false, but when set to true, is permanently true. Let's public see that it is off forever.
    address bpSwapPairRouterPool;           // ie. Uniswap V2 ETH-REMN Pool (router) for bot protected buy/sell, add after pool established.
    mapping (address => uint256) public bpAddressTimesTransacted;   // Mapped value counts number of times transacted (2 max per address during bp)
    mapping (address => bool) public bpBlacklisted;                 // If wallet tries to trade after liquidity is added but before owner sets trading on, wallet is blacklisted

    constructor() ERC20("Remnant", "REMN") {
        _mint(ADDRESS_TEAM, INITIAL_AMOUNT_TEAM * 10 ** 18);
        _mint(ADDRESS_STAKING, INITIAL_AMOUNT_STAKING * 10 ** 18);
        _mint(ADDRESS_ECOSYSTEM, INITIAL_AMOUNT_ECOSYSTEM * 10 ** 18);
        _mint(ADDRESS_OTHER, INITIAL_AMOUNT_OTHER * 10 ** 18);

        // Default values for bp (bot protection), adjustable
        bpAllowedNumberOfTx = 2;                // Max 2 buy or sell swaps (either) per wallet, during bot protection
        bpMaxGas = 501 * 10 ** 18;              // Default gwei max = 501
        bpMaxBuyAmount = 3670001 * 10 ** 18;    // Default max buy tokens = 3,670,001 (approximately 0.50% of initial circulating supply)
        bpMaxSellAmount = 3670001 * 10 ** 18;   // Default max sell tokens = 3,670,001 (approximately 0.50% of initial circulating supply)
    }

    /**
     * @dev Toggles bot protection, blocking suspicious transactions during liquidity events.
     */
    function bpToggleOnOff() external onlyOwner {
        bpEnabled = !bpEnabled;
    }

    /**
     * @dev Sets max gwei allowed in transaction when bot protection is on.
     */
    function bpSetMaxGwei(uint256 gweiAmount) external onlyOwner {
        bpMaxGas = gweiAmount;
    }

    /**
     * @dev Sets max buy value when bot protection is on.
     */
    function bpSetMaxBuyValue(uint256 val) external onlyOwner {
        bpMaxBuyAmount = val;
    }

     /**
     * @dev Sets max sell value when bot protection is on.
     */
    function bpSetMaxSellValue(uint256 val) external onlyOwner {
        bpMaxSellAmount = val;
    }

    /**
     * @dev Sets swap pair pool address (i.e. Uniswap V2 ETH-REMN pool, for bot protection)
     */
    function bpSetSwapPairPool(address addr) external onlyOwner {
        bpSwapPairRouterPool = addr;
    }

    /**
     * @dev Turns off bot protection permanently.
     */
    function bpDisablePermanently() external onlyOwner {
        bpEnabled = false;
        bpPermanentlyDisabled = true;
    }

    /**
     * @dev Toggles trading (requires bp not permanently disabled)
     */
    function bpToggleTrading() external onlyOwner {
        require(!bpPermanentlyDisabled, "Cannot toggle when bot protection is already disabled permanently");
        bpTradingEnabled = !bpTradingEnabled;
    }

    /**
     * @dev Check before token transfer if bot protection is on, to block suspicious transactions
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Bot/snipe protection requirements if bp (bot protection) is on, and is not already permanently disabled
        if (bpEnabled && !bpPermanentlyDisabled && msg.sender != owner()) {
            require(!bpBlacklisted[from] && !bpBlacklisted[to], "BP: Account is blacklisted"); // Must not be blacklisted
            require(tx.gasprice <= bpMaxGas, "BP: Gas setting exceeds allowed limit"); // Must set gas below allowed limit
        
            // If user is buying (from swap), check that the buy amount is less than the limit (this will not block other transfers unrelated to swap liquidity)
            if (bpSwapPairRouterPool == from) {
                require(amount <= bpMaxBuyAmount, "BP: Buy exceeds allowed limit"); // Cannot buy more than allowed limit
                require(bpAddressTimesTransacted[to] < bpAllowedNumberOfTx, "BP: Exceeded number of allowed transactions");
                if (!bpTradingEnabled) {
                    bpBlacklisted[to] = true; // Blacklist wallet if it tries to trade (i.e. bot automatically trying to snipe liquidity)
                    revert SwapNotEnabledYet(); // Revert with error message
                } else {
                    bpAddressTimesTransacted[to] += 1; // User has passed transaction conditions, so add to mapping (to limit user to 2 transactions)
                }
            // If user is selling (from swap), check that the sell amount is less than the limit. The code is mostly repeated to avoid declaring variable and wasting gas.
            } else if (bpSwapPairRouterPool == to) {
                require(amount <= bpMaxSellAmount, "BP: Sell exceeds limit"); // Cannot sell more than allowed limit
                require(bpAddressTimesTransacted[from] < bpAllowedNumberOfTx, "BP: Exceeded number of allowed transactions");
                if (!bpTradingEnabled) {
                    bpBlacklisted[from] = true; // Blacklist wallet if it tries to trade (i.e. bot automatically trying to snipe liquidity)
                    revert SwapNotEnabledYet(); // Revert with error message
                } else {
                    bpAddressTimesTransacted[from] += 1; // User has passed transaction conditions, so add to mapping (to limit user to 2 transactions)
                }
            }
        }
        super._beforeTokenTransfer(from, to, amount);
    }

}
