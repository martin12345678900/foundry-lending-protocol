// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// // Invariants:
// // protocol must never be insolvent / undercollateralized
// // users cant create stablecoins with a bad health factor
// // a user should only be able to be liquidated if they have a bad health factor

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DSCEngine s_dscEngine;
    DecentralizedStableCoin s_dsc;
    HelperConfig helperConfig;
    DeployDSCEngine deployer;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSCEngine();
        (s_dsc, s_dscEngine, helperConfig) = deployer.run();

        (weth,wbtc,,,) = helperConfig.activeNetworkConfig();
        handler = new Handler(s_dscEngine, s_dsc, weth, wbtc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
        uint256 totalSupply = s_dsc.totalSupply();
        uint256 wethDeposted = IERC20(weth).balanceOf(address(s_dscEngine));
        uint256 wbtcDeposited = IERC20(wbtc).balanceOf(address(s_dscEngine));

        uint256 wethValue = s_dscEngine.getUsdValue(weth, wethDeposted);
        uint256 wbtcValue = s_dscEngine.getUsdValue(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}