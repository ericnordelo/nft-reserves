// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceOracle {
    /**
     * @notice get the price of a token
     * @param token the token address for price retrieval
     * @return currentPrice Price denominated in USD, with 6 decimals, for the given token address
     */
    function price(address token) external view returns (uint256 currentPrice);
}
