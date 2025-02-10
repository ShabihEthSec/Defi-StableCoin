// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call the function. (save our runs from being wasted.)

pragma solidity ^0.8.18;

 import {Test, console} from "forge-std/Test.sol";
 import {DSCEngine} from "../../src/DSCEngine.sol";
 import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
 import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
 import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


 contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithDepositedCollateral;
    MockV3Aggregator public ethUsdPriceFeed;


    uint256 private constant AMOUNT_COLLATERAL = 10e18;
    uint256 private MAX_DEPOSIT_SIZE = type(uint96).max;
    constructor (DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(address(collateralTokens[0]));
        wbtc = ERC20Mock(address(collateralTokens[1]));

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        
    }

 

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithDepositedCollateral.length == 0) {
            return;
        }
        address sender = usersWithDepositedCollateral[addressSeed % usersWithDepositedCollateral.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = int256(collateralValueInUsd / 2) - int256(totalDscMinted);
        console.log("totalDscMinted: ", totalDscMinted);
        console.log("collateralValueInUsd: ", collateralValueInUsd);
        console.log("maxDscToMint: ", maxDscToMint);
        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
     }


    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public  {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.approve(address(dsce), type(uint256).max);
        collateral.mint(msg.sender, 10e18);
        dsce.depositCollateral(address(collateral), 10e18);
        vm.stopPrank();
        // UsersWhoDeposited
        usersWithDepositedCollateral.push(msg.sender);

    }


    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0){
            return;
        }

        dsce.redeemCollateral(address(collateral), amountCollateral);
        
    }

    function updateCollateralPrice(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        ethUsdPriceFeed.updateAnswer(newPriceInt);
    }

    // Helper functions
    function  _getCollateralFromSeed(uint256 collateralSeed) public view returns(ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth; 
        }
        else return wbtc;
    }

 
 }