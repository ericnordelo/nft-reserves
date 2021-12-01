// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PriceOracleMock {
    mapping(address => uint256) private _prices;

    /**
     * @notice get the price of a token
     * @param token_ the token address for price retrieval
     * @return currentPrice Price denominated in USD, with 6 decimals, for the given token address
     */
    function price(address token_) external view returns (uint256 currentPrice) {
        return _prices[token_] > 0 ? _prices[token_] : 1000000;
    }

    function setPrice(address token_, uint256 value_) external {
        _prices[token_] = value_;
    }
}
