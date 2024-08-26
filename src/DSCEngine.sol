// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceFeedLibrary} from "./lib/PriceFeedLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    /**
     * Libraries
     */
    using PriceFeedLibrary for AggregatorV3Interface;
    /**
     * Errors
     */

    error DSCEngine__MoreThanZero();
    error DSCEngine__TransferFailed();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__BrokenHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOk();

    /**
     * State Variables
     */
    uint256 private constant DSC_VALUE_IN_USD = 1;
    uint256 private constant MIN_HEALTH_FACTOR = 100; // 1 * 100
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_LIQUIDATOR_BONUS = 10;

    mapping(address user => mapping(address collateralToken => uint256 amountCollateral)) private
        s_userCollateralDeposited;
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    /**
     * Events
     */
    event DepositCollateral(address indexed sender, address indexed collateralToken, uint256 amount);
    event RedeemCollateral(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed collateralToken, uint256 amount
    );

    /**
     * Modifiers
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address collateralToken) {
        if (s_priceFeeds[collateralToken] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /**
     * Functions
     */
    constructor(address[] memory collateralTokens, address[] memory priceFeeds, address dscAddress) {
        if (collateralTokens.length != priceFeeds.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            s_priceFeeds[collateralTokens[i]] = priceFeeds[i];
            s_collateralTokens.push(collateralTokens[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDSC(address collateralToken, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        depositCollateral(collateralToken, amountCollateral);
        mintDSC(amountDscToMint);
    }

    function depositCollateral(address collateralToken, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(collateralToken)
        nonReentrant
    {
        s_userCollateralDeposited[msg.sender][collateralToken] += amountCollateral;
        emit DepositCollateral(msg.sender, collateralToken, amountCollateral);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDSC(address collateralToken, uint256 amountCollateralToReedeem, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(collateralToken, amountCollateralToReedeem, msg.sender, msg.sender);
    }

    function redeemCollateral(address collateralToken, uint256 amountCollateral, address from, address to)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(collateralToken)
        nonReentrant
    {
        _redeemCollateral(collateralToken, amountCollateral, from, to);
        // Check the health factor if we have more DSC tokens(in $) than the deposited collateral tokens(in $)
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDSC(msg.sender, msg.sender, amountDscToBurn);
    }

    // $100 ETH backing $50 DSC
    // If price of ether for this amount goes to $20 since we have $50 DSC -> DSC isn't worth $1(as it should be)!!!
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 userHealthFactor = _healthFactor(user);
        // Check if the health factor of the user is ok, if it's ok we are not able to liquidate him
        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOk();
        }

        // 0.11 token -> liquidator
        uint256 tokenAmountFromDebtCovered =
            getTokenAmountFromUsd(collateralToken, debtToCover + ((ADDITIONAL_LIQUIDATOR_BONUS / 100) * debtToCover));
        _redeemCollateral(collateralToken, tokenAmountFromDebtCovered, user, msg.sender);
        _burnDSC(user, msg.sender, debtToCover * DSC_VALUE_IN_USD);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // This functions calculates how close the user is to liquidation. If the health factor goes below 100, he could be liquidated
    function _healthFactor(address user) private view returns (uint256) {
        uint256 totalCollateralInUSDForUser = calculateTotalCollateralForUser(user);
        // total value in minted DSC tokens in USD 
        uint256 totalMintedDSCTokensInUsd = s_DSCMinted[user] * DSC_VALUE_IN_USD;

        uint256 totalCollateralAdjustedForThreshold =
            (totalCollateralInUSDForUser * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 healthFactor = (totalCollateralAdjustedForThreshold * 100) / totalMintedDSCTokensInUsd;

        return healthFactor;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Check later
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokenHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address collateralToken, uint256 amountCollateral, address from, address to) private {
        // If the caller tries to redeem more that he has deposited, solidity compiler will throw an error
        s_userCollateralDeposited[from][collateralToken] -= amountCollateral;
        emit RedeemCollateral(from, to, collateralToken, amountCollateral);

        bool success = IERC20(collateralToken).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) internal {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        // transfering the tokens that we want to burn to the DSCEngine since DSC tokens are under it's control
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // After they are transfered to the DSCEngine we are burning them
        i_dsc.burn(amountDscToBurn);
    }

    function calculateTotalCollateralForUser(address user) public view returns (uint256 totalCollateralInUSD) {
        address[] memory _collateralTokens = s_collateralTokens;

        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address collateralToken = _collateralTokens[i];
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
            uint256 collateralTokenPriceInDollars = priceFeed.getLatestPrice();
            uint256 amountDepositedCollateralToken = s_userCollateralDeposited[user][collateralToken];

            // 10 * 2000 = 20,000
            totalCollateralInUSD += amountDepositedCollateralToken * collateralTokenPriceInDollars;
        }

        return totalCollateralInUSD;
    }

    function getTokenAmountFromUsd(address collateralToken, uint256 amountInUsd)
        public
        view
        isAllowedToken(collateralToken)
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        uint256 collateralTokenPriceInDollars = priceFeed.getLatestPrice();

        return amountInUsd / collateralTokenPriceInDollars;
    }

    function getUsdValue(address collateralToken, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        uint256 collateralTokenPriceInDollars = priceFeed.getLatestPrice();
        uint256 totalUsdValue = collateralTokenPriceInDollars * amount;

        return totalUsdValue;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = calculateTotalCollateralForUser(user);

        return (totalDscMinted, totalCollateralValueInUsd);
    }
}
