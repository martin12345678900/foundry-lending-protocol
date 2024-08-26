// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSCEngine is Script {
    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address weth, address wbtc, address ethToUsdPriceFeed, address btcToUsdPriceFeed,) =
            helperConfig.activeNetworkConfig();
        vm.startBroadcast();

        DecentralizedStableCoin dsc = new DecentralizedStableCoin();

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = weth;
        collateralTokens[1] = wbtc;

        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = ethToUsdPriceFeed;
        priceFeeds[1] = btcToUsdPriceFeed;

        DSCEngine dscEngine = new DSCEngine(collateralTokens, priceFeeds, address(dsc));

        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}
