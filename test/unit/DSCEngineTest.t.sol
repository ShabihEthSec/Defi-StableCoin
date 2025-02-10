// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    

    uint256 public STARTING_ERC20_BALANCE = 100e18;   
    uint256 public APPROVED_SPENDING_AMOUNT = 10e18;
    uint256 public AMOUNT_COLLATERAL = 10e18;
    uint256 public AMOUNT_DSC_TO_MINT = 5e18;
    uint256 public AMOUNT_DSC_TO_BURN = 5e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
        vm.deal(USER, STARTING_ERC20_BALANCE);


        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////////////
    ///// Constructor Test ////////////
    //////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenAddressesLengthDoesntMatchProceFeeds() public {
        tokenAddresses.push(weth);
        // tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

    }

    ///////////////////////////////////
    //////// Price Test ///////////////
    //////////////////////////////////

    function testGetUsdValue() public view {
        // 15e18 * 2000/ETH = 30,000e18;
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2000/ ETH, 100
        uint256 expectedWeth = 0.05 ether; 
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////////////
    ///// Deposit Collateral Test /////
    ///////////////////////////////////

    function testRevertDepositCollateralIfZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(this), APPROVED_SPENDING_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier DSCMinted() {
        testDepositCollateralAndMintDsc();
        _;
    }


    // 1-i: s_collateralDeposited
    function testCollateralDepsitedMappingReturnsCorrectValue() public depositedCollateral {
        uint256 expectedCollateralValue = AMOUNT_COLLATERAL;
        uint256 actualCollateralValue = dsce.s_collateralDeposited(USER, weth);
        console.log(actualCollateralValue);
        assertEq(expectedCollateralValue, actualCollateralValue);
    }

    // 1-ii: s-collateralTokens[]

    function testCollateralTokensArrayHoldsTheTokenAddresses() public depositedCollateral {
        address wethAddress = weth;
        address wbtcAddress = wbtc;
        address tokenAddressStoredInArray = dsce.s_collateralTokens(0);
        address wbtcAddressStoredInArray = dsce.s_collateralTokens(1);
        uint256 expectedCollateralTokenArrayLength = 2;
        uint256 actualCollateralTokenArrayLength = dsce.getTokenCollateralArrayLength();

        assertEq(expectedCollateralTokenArrayLength, actualCollateralTokenArrayLength);
        assertEq(wethAddress, tokenAddressStoredInArray);
        assertEq(wbtcAddress, wbtcAddressStoredInArray);
    }

    // 2.
    function testGetAccountCollateralValue() public depositedCollateral {
        // dsce.getAccountCollateralValue(USER);
        console.log(dsce.getAccountCollateralValue(USER));
    }

    function testGetUsdValueForModifier() public depositedCollateral {
        uint256 usdValueOfCollateralToken = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        console.log(usdValueOfCollateralToken); 
    }

    function testCanDepositAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        console.log(AMOUNT_COLLATERAL);
        console.log(collateralValueInUsd);
        uint256 expectedTotalDscMinted = 0;
        console.log(weth, collateralValueInUsd);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }


    ///////////////////////////////////
    //////// Minting DSC Test /////////
    ///////////////////////////////////

    function testMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);


        vm.stopPrank();
        uint256 expectedDscMinted = AMOUNT_DSC_TO_MINT;
        (uint256 totalDscMinted, ) =  dsce.getAccountInformation(USER);
        assertEq(expectedDscMinted,totalDscMinted);

    }

    function testDepositCollateralAndMintDsc() public  {
        vm.startPrank(USER);
        
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        uint256 expectedDSCMinted = AMOUNT_DSC_TO_MINT;
        (uint256 totalDSCMinted,) = dsce.getAccountInformation(USER);
        assertEq(expectedDSCMinted, totalDSCMinted);
    }

    ///////////////////////////////////
    ////// Redeem Collateral Test /////
    ///////////////////////////////////

    // 2000000000000000000000

    function testRedeemCollateral() public depositedCollateral { // @error
        uint256 balanceBeforeRedeemingCollateral = ERC20Mock(weth).balanceOf(USER);
        console.log(balanceBeforeRedeemingCollateral);
        vm.prank(USER);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 balanceAfterRedeemingCollateral = ERC20Mock(weth).balanceOf(USER);
        console.log(balanceAfterRedeemingCollateral);
        assert(balanceBeforeRedeemingCollateral != balanceAfterRedeemingCollateral);
    }

    function testRevertsWhenRedeemCollateralValueIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    

    // function testRedeemCollateralEmitEventWithCorrectArgs() public depositedCollateral{
    //     dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
    //     vm.expectEmit(true, true, true, true);   
    //     emit CollateralRedeemed(dsce, USER, weth, AMOUNT_COLLATERAL);
    // }

    

    // function testLiquidation() public DSCMinted {
    //     uint256 healthFactor = dsce.getHealthFactor(USER);
    //     console.log(healthFactor);
    //     dsce.liquidate();

    // }

    // function testBurnDSC() public DSCMinted {
    //     vm.startPrank(USER);
    //     dsce.burnDsc(AMOUNT_DSC_TO_BURN);
    //     vm.stopPrank();

    // }



    
    function testRevertMintDscIfZero() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertIfTokenNotAllowed() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(this), APPROVED_SPENDING_AMOUNT);
        vm.expectRevert();
        dsce.depositCollateral(address(0), 1e18);
    }

    function testDepositingCollateralUpdatesTheDataStructure() public depositedCollateral {
        vm.startPrank(USER);
        
        ERC20Mock(weth).approve(address(dsce), APPROVED_SPENDING_AMOUNT);
        dsce.depositCollateral(weth, 1e17);
        vm.stopPrank();
    }
}