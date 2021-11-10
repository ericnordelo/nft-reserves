// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IPriceOracle} from "../interface/IPriceOracle.sol";

contract PriceOracleMock is IPriceOracle {
  constructor() public {
  }
  function decimals(address) external view returns (uint256 _decimals) {
      _decimals = 0;
  }

  function price(address) external view returns (uint256 price) {
      price = 0;
  }
}
