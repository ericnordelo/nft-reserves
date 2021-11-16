// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface INFTVault {
  function owner(address, uint256) external returns(address);

  function lockNFT(address, uint256) external;

  function unlockNFT(address, uint256) external;

  function transferNFT(address, uint256, address) external;
}
