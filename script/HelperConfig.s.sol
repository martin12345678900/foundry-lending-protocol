// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        address wbtc;
        address ethToUsdPriceFeed;
        address btcToUsdPriceFeed;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint8 public constant DECIMALS = 8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        // If we are on Sepolia Chain
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
            // If we are on local anvil chain
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            // WETH, WBTC
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            // ETH/USD, BTC/USD Price Feeds
            ethToUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcToUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Means we already have deployed the network config helper contract
        if (activeNetworkConfig.ethToUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();

        ERC20Mock wethMock = new ERC20Mock();
        ERC20Mock wbtcMock = new ERC20Mock();

        MockV3Aggregator ethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

        vm.stopBroadcast();

        // Return it's address
        return NetworkConfig({
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            ethToUsdPriceFeed: address(ethPriceFeed),
            btcToUsdPriceFeed: address(btcPriceFeed),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
