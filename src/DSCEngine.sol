// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Shabih "AbdulHafeez" Hasan
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 * Our DSC system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic for minting and redeeming DSC, as well as
 * depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system.
 */
contract DSCEngine is ReentrancyGuard {
    //////////////////////////////////
    //////////// Errors //////////////
    //////////////////////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOkay();
    error  DSCEngine__HealthFactorNotImproved();

    //////////////////////////////////
    /////// State Variables  /////////
    //////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18; 
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollatarolized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATOR_BONUS = 10; // This means a 10% bonus 
    
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) public s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;

    address[] public s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;


    //////////////////////////////////
    //////////// Events //////////////
    //////////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256  amountCollateral);


    //////////////////////////////////
    //////////// Modifiers //////////
    //////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    //////////////////////////////////
    //////////// Functions //////////
    //////////////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////////////
    /////// External Functions ///////
    //////////////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral 
     * @param amountCollateral The amount to deposit as collateral
     * @param amountDscToMint The amount of Decentralized StableCoin to mint
     * @notice This function will deposit collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress) {
            depositCollateral(tokenCollateralAddress, amountCollateral);
            mintDsc(amountDscToMint);

        }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateralto deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /** 
     *@param tokenCollateralAddress the collateral address to redeem
     * @param amountCollateral The amount of Collateral to redeem
     * @param amountDscToBurn The amount if DSC to burn
     * @notice This function burns DSC and redeems Underlying Collateral in transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeem collateral already checks health factor
    }

    // in order to redeem collateral 
    // 1. health factor must be over 1 AFTER collateral is pulled 
    // DRY: Don't Repeat Yourself

    // CEI: Check, Effects, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) /*nonReentrant*/ {
        // s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        // emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        // // _calculateHealthFactor()
        // bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        // if (!success) {
        //     revert DSCEngine__TransferFailed();
        // }
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);  // @error: causing error, when redeeming collateral without DSC coins.

    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountDscToMint);
        // this condition is hypothetically unreachable
        if(!success) {
            revert DSCEngine__MintFailed();
        }
    }
    
    // Do we need to check if this break health factor? // No, because its highly unlikely that burning the debt/ removing your debt is going to break the health factor.
    function burnDsc(uint256 amount) public {
        _burnDSC(msg.sender, msg.sender, amount);
        // s_DscMinted[msg.sender] -= amount;
        // bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        // if (!success) {
        //     revert DSCEngine__TransferFailed();
        // }
        // i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    // If we do start nearing undercollateralization, we need someone to liquidate positions

    // $100 ETH backing $50 DSC
    // $20 ETH back $50 DSC <- DSC isn't worth $1!!!


    // $75 backing $50 DSC
    // Liquidator take $75 backing and burns off the $50 DSC


    // If someone is almost undercollateralized, we will pay to liquidate them!

    /**
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthfactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor 
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the user funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized 
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we would'nt be able to incentivized the liquidators.
     * For Example: If the price of the collateral plummeted before anyone could be liquidated.  
     * 
     * Follows CEI: Checks, Effects, Interactions
     */
    
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOkay();
        }
        // We want to burn their DSC "debt"
        // And take their collateral
        // Bad Users: $140 ETH, $100 DSC 
        // DebtToCover = $100
        // $100 DSC == ??? ETH?
        // 0.05 ETH
        uint256 tokenAmountFromDebtToCovered = getTokenAmountFromUsd(collateral, debtToCover);  
        // and give them a 10% bonus
        // so we are giving the liquidator $110 weth for $100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury

        // 0.05 * 0.1 = 0.005. Getting 0.055
        uint256 bonusCollateral = (tokenAmountFromDebtToCovered * LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtToCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        // we need to burn the DSC on behalf of the user
        _burnDSC(user, msg.sender, debtToCover);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

    }

    // function getHealthFactor() external view {}

    ///////////////////////////////////////
    // Private & Internal View Functions //
    ///////////////////////////////////////

    /**
     * Returns how close to liquidation a user is 
     * If a user's health  goes below 1, then they can get liquidated
     */

    /**
     * 
     * Low-level internal functions, do not call unless the function calling it checking for health factor
     * 
     */
    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) internal {
         s_DscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        
    }

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }


    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // _calculateHealthFactor()
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }


    function _healthFactor(address user) private view returns(uint256) {
        // total DSC minted
        // total Collateral VALUE (not just 'total collateral' but the 'VALUE of the total collateral')

        // require(totalDscMinted != 0, "Can Not divide by zero!");
        uint256 healthFactor;
        return healthFactor = _calculateHealthFactor(user);
        
    }

    function _calculateHealthFactor(address user) private view returns(uint256) {

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    } 

        // 1. Check health factor(do they have enough collateral)
        // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR)
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
    }

    

    ///////////////////////////////////////
    // Public & External View Functions ///
    ///////////////////////////////////////

    

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256) {
        // price of ETH (token)
        // $2000 ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , ,) = priceFeed.latestRoundData();
        //     ($10e18 * 1e18) / (1e8 * 1e10);
        // = 0.005000000000000000 = 0.05 ETH
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 tokenCollateralValueInUsd) { // ATTENTION: this function is not returning correct output!!!!

        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value
        for (uint256 i=0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i]; // working fine
            uint256 amount = s_collateralDeposited[user][token]; // working fine
            uint256 tokenValue = getUsdValue(token, amount); //@Bug: Added this statement
            tokenCollateralValueInUsd += tokenValue;         //@Bug: And This one   
        }
        return tokenCollateralValueInUsd;
    }

    function calculateHealthFactor(address user) public view returns(uint256) {
        return _calculateHealthFactor(user);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
         // 1 ETH = $1000
         // returned value from CL will be 1000 * 1e8
         return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (1000 * 1e8)
    }

    ///////////////////////////////////
    ///////////// GETTERS /////////////
    ///////////////////////////////////

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
          (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
          return (totalDscMinted, collateralValueInUsd);
    }

    function getTokenCollateralArrayLength() public view returns(uint256) {
        return s_collateralTokens.length;
    }
    
    function getHealthFactor(address user) external view returns(uint256 ) {
        uint256 healthFactor = _healthFactor(user);
        return healthFactor;
    }

    function getCollateralTokens() external view returns (address[] memory ) {
    return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address collateralAddress) public view returns (uint256) {
        return s_collateralDeposited[user][collateralAddress];
    }

    function getCollateralTokenPriceFeed(address priceFeed) public view returns (address) {
        return s_priceFeeds[priceFeed];
    }
}
