// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    address weth;
    address wbtc;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc, address _weth, address _wbtc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        weth = _weth;
        wbtc = _wbtc;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateralToken = _getCollateralToken(collateralSeed);
        console.log("collateralToken:", collateralToken);
        dscEngine.depositCollateral(collateralToken, amountCollateral);
    }

    function _getCollateralToken(uint256 collateralSeed) private view returns(address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}