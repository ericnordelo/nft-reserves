// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IPriceOracle} from "../interface/IPriceOracle.sol";

contract PriceOracleMock is IPriceOracle {
    function decimals(address) external pure override returns (uint256 _decimals) {
        _decimals = 0;
    }

    function price(address) external pure override returns (uint256 _price) {
        _price = 0;
    }
}
