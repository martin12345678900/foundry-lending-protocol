// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";

contract DSCEngineTest is Test {
    /**
     * Events
     */
    event DepositCollateral(address indexed sender, address indexed collateralToken, uint256 amount);
    event RedeemCollateral(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed collateralToken, uint256 amount
    );

    DSCEngine s_dscEngine;
    DecentralizedStableCoin s_dsc;

    address weth;
    address wbtc;
    address ethToUsdPriceFeed;
    address btcToUsdPriceFeed;

    uint256 public constant DEPOSIT_COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant MINT_DEPOSIT_AMOUNT = 0.1 ether;
    uint256 public constant LIQUIDATOR_DEPOSIT_AMOUNT = 0.25 ether;
    uint256 public constant REDEEM_COLLATERAL_AMOUNT = 0.075 ether;
    uint256 public constant INVALID_DSC_TO_MINT_AMOUNT = 200 ether;
    uint256 public constant VALID_DSC_TO_MINT_AMOUNT = 50 ether;
    uint256 public constant DSC_TO_BURN_AMOUNT = 25 ether;
    uint256 public constant DEBT_BONUS = 10;

    int256 public constant ETH_USD_PRICE = 2000e8;

    address USER = makeAddr("Martin");
    address LIQUIDATOR = makeAddr("LIQUIDATOR");

    function setUp() external {
        // s_fundMe = new FundMe(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        DeployDSCEngine deployer = new DeployDSCEngine();
        (DecentralizedStableCoin dsc, DSCEngine dscEngine, HelperConfig helperConfig) = deployer.run();
        s_dsc = dsc;
        s_dscEngine = dscEngine;
        (weth, wbtc, ethToUsdPriceFeed, btcToUsdPriceFeed,) = helperConfig.activeNetworkConfig();

        // Mint to user some weth and wbtc
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);

        // Mint to liquidator some weth and wbtc
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);

    }

    address[] public tokens;
    address[] public priceFeeds;

    /**
     * Constructor tests
     */
    function testNotProperInitializationOfConstuctor() public {
        tokens.push(weth);
        priceFeeds.push(ethToUsdPriceFeed);
        priceFeeds.push(btcToUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokens, priceFeeds, address(s_dsc));
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 expectedTokenAmount = 0.05 ether;
        uint256 tokenAmountFromUsd = s_dscEngine.getTokenAmountFromUsd(weth, 100 ether);

        // 100$ of WETH with price of 1WETH = 2000$ -> expected should be 100 / 200 -> 0.05 ether
        assert(expectedTokenAmount == tokenAmountFromUsd);
    }

    function testDepositCollateralWithZeroAmount() public {
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        s_dscEngine.depositCollateral(weth, 0);
    }

    function testDepositCollateralWithInvalidToken() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        s_dscEngine.depositCollateral(address(randomToken), DEPOSIT_COLLATERAL_AMOUNT);
    }

    modifier depositCollateral(uint256 collateralTokensAmount) {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(s_dscEngine), DEPOSIT_COLLATERAL_AMOUNT);

        s_dscEngine.depositCollateral(weth, collateralTokensAmount);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDSC(uint256 collateralTokensAmount) {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(s_dscEngine), DEPOSIT_COLLATERAL_AMOUNT);
        s_dsc.approve(address(s_dscEngine), VALID_DSC_TO_MINT_AMOUNT);
        s_dscEngine.depositCollateralAndMintDSC(weth, collateralTokensAmount, VALID_DSC_TO_MINT_AMOUNT);

        vm.stopPrank();
        _;
    }

    function testDepositCollateralEmitsDepositEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(s_dscEngine), DEPOSIT_COLLATERAL_AMOUNT);

        vm.expectEmit(true, true, false, false, address(s_dscEngine));

        emit DepositCollateral(USER, weth, DEPOSIT_COLLATERAL_AMOUNT);
        // DEPOSITED 100 in WETH
        s_dscEngine.depositCollateral(weth, DEPOSIT_COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollateralIncreasesUserDepositAndSendsTheTokensToTheProtocol() public depositCollateral(DEPOSIT_COLLATERAL_AMOUNT) {
    
        uint256 balanceOfCollateralTokenOnDSCEngine = ERC20Mock(weth).balanceOf(address(s_dscEngine));
        
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = s_dscEngine.getAccountInformation(USER);
        uint256 collateralTokenAmountFromUsd = s_dscEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);

        
        assert(balanceOfCollateralTokenOnDSCEngine == DEPOSIT_COLLATERAL_AMOUNT);
        assert(totalDscMinted == 0);
        assert(collateralTokenAmountFromUsd == DEPOSIT_COLLATERAL_AMOUNT);
    }

    function testMintWithZeroAmount() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        s_dscEngine.mintDSC(0);
    }

    // USER -> WETH -> 100 WETH TOKENS
    // MintDSC(150 DSC TOKEN)
    function testMintBreaksTheHealthFactor() public depositCollateral(MINT_DEPOSIT_AMOUNT) {
        uint256 expectedUserHealthFactor = 50;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, expectedUserHealthFactor));
        s_dscEngine.mintDSC(INVALID_DSC_TO_MINT_AMOUNT);
    }

    function testMintWorksProperly() public depositCollateral(MINT_DEPOSIT_AMOUNT) {
        vm.prank(USER);
        s_dscEngine.mintDSC(VALID_DSC_TO_MINT_AMOUNT);
        uint256 mintedUserDSCTokens = s_dsc.balanceOf(USER);

        assert(mintedUserDSCTokens == VALID_DSC_TO_MINT_AMOUNT);
    }


    // Deposited WETH (200$ in USD)
    // We want to redeem them checking the healthFactor after that
    function testRedeemCollateralGivesBackCollateralToTheUser() public {
        uint256 initialUserCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(s_dscEngine), DEPOSIT_COLLATERAL_AMOUNT);
        // DEPOSITED $20.000 in WETH, minted 50$ in DSC
        s_dscEngine.depositCollateralAndMintDSC(weth, DEPOSIT_COLLATERAL_AMOUNT, VALID_DSC_TO_MINT_AMOUNT);
        vm.expectEmit(true, true, true, false, address(s_dscEngine));

        emit RedeemCollateral(USER, USER, weth, REDEEM_COLLATERAL_AMOUNT);

        s_dscEngine.redeemCollateral(weth, REDEEM_COLLATERAL_AMOUNT, USER, USER);
        vm.stopPrank();

        uint256 endingUserCollateralBalance = ERC20Mock(weth).balanceOf(USER);
        
        assert(endingUserCollateralBalance + (DEPOSIT_COLLATERAL_AMOUNT - REDEEM_COLLATERAL_AMOUNT) == initialUserCollateralBalance);
    }

    function testRedeemCollateralBreaksTheHealthFactor() public depositCollateralAndMintDSC(MINT_DEPOSIT_AMOUNT) {
        vm.startPrank(USER);
        // DEPOSITED WETH = 0.1 - 0.075 = 0.05 -> 50$ in WETH -> 50$ in DSC -> healhFactor < 1;
        uint256 expectedUserHealthFactor = 50;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, expectedUserHealthFactor));
        s_dscEngine.redeemCollateral(weth, REDEEM_COLLATERAL_AMOUNT, USER, USER);
    }

    function testBurnDSC() public depositCollateralAndMintDSC(DEPOSIT_COLLATERAL_AMOUNT) {
        uint256 dscBalanceOfUserAfterMinting = s_dsc.balanceOf(USER);
        vm.startPrank(USER);        
        s_dscEngine.redeemCollateralForDSC(weth, REDEEM_COLLATERAL_AMOUNT, DSC_TO_BURN_AMOUNT);
        vm.stopPrank();
        uint256 dscBalanceOfUserAfterBurning = s_dsc.balanceOf(USER);

        assert(dscBalanceOfUserAfterBurning + DSC_TO_BURN_AMOUNT == dscBalanceOfUserAfterMinting);
    }

    // DEPOSIT $200 in WETH, mint $50 in DSC
    function testCantLiquidateUserWithGoodHealthFactor() public depositCollateralAndMintDSC(MINT_DEPOSIT_AMOUNT) {
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOk.selector);
        s_dscEngine.liquidate(weth, USER, VALID_DSC_TO_MINT_AMOUNT);
    }

    // DEPOSIT $200(0.1 ether) in WETH, mint $50 in DSC
    function testLiquidationOfUser() public depositCollateralAndMintDSC(MINT_DEPOSIT_AMOUNT) {
        // Now ethPrice = 500$
        int updatedEthPrice = 500e8;

        vm.startPrank(LIQUIDATOR);
        // If before 0.1 ether == $200 -> after update -> 50$ in WETH -> means he should be liquidated
        MockV3Aggregator(ethToUsdPriceFeed).updateAnswer(updatedEthPrice);
        
        // Deposit some weth for liquidator and mint some tokens
        ERC20Mock(weth).approve(address(s_dscEngine), DEPOSIT_COLLATERAL_AMOUNT);
        s_dsc.approve(address(s_dscEngine), VALID_DSC_TO_MINT_AMOUNT);
        // 0.25eth => 125$ in WETH, and minting $50 DSC -> health factor > 1 (Ok)
        // 0.25 ether, 50 DSC tokens
        s_dscEngine.depositCollateralAndMintDSC(weth, LIQUIDATOR_DEPOSIT_AMOUNT, VALID_DSC_TO_MINT_AMOUNT);

        uint256 startingBalanceWethOfLiquidator = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 startingBalanceDscOfLiquidator = s_dsc.balanceOf(LIQUIDATOR); 

        s_dscEngine.liquidate(weth, USER, VALID_DSC_TO_MINT_AMOUNT);
        vm.stopPrank();

        uint256 reward = VALID_DSC_TO_MINT_AMOUNT + ((DEBT_BONUS / 100) * VALID_DSC_TO_MINT_AMOUNT);
        uint256 liquidatorRewardInTokens = s_dscEngine.getTokenAmountFromUsd(weth, reward);

        uint256 endingBalanceWethOfLiquidator = startingBalanceWethOfLiquidator + liquidatorRewardInTokens;
        uint256 endingBalanceDscOfLiquidator = startingBalanceDscOfLiquidator - VALID_DSC_TO_MINT_AMOUNT;


        assert(ERC20Mock(weth).balanceOf(LIQUIDATOR) == endingBalanceWethOfLiquidator);
        assert(s_dsc.balanceOf(LIQUIDATOR) == endingBalanceDscOfLiquidator);
    }
}
