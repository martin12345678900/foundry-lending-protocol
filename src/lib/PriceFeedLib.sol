// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library PriceFeedLibrary {
    /**
     * @dev Returns the latest price from the AggregatorV3Interface in readable USD format.
     * @param feed The price feed contract instance.
     * @return The latest price in USD, scaled down to remove extra decimals.
     */
    function getLatestPrice(AggregatorV3Interface feed) internal view returns (uint256) {
        (
            /* uint80 roundID */,
            int256 answer,
            /* uint256 startedAt */,
            /* uint256 timeStamp */,
            /* uint80 answeredInRound */
        ) = feed.latestRoundData();

        // Get the number of decimals used by the price feed
        uint8 decimals = feed.decimals();

        // Convert the answer to a human-readable USD value
        // Ensure the answer is positive before casting to uint
        return uint256(answer) / (10 ** decimals);
    }

    /**
     * @dev Returns the number of decimals used by the price feed.
     * @param feed The price feed contract instance.
     * @return The number of decimals.
     */
    function getDecimals(AggregatorV3Interface feed) internal view returns (uint8) {
        return feed.decimals();
    }
}