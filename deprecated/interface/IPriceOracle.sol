// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IPriceOracle {
  function decimals(address) external view returns (uint256 _decimals);

  function price(address) external view returns (uint256 price);
}
