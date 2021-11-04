// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface INFTVault {
  function lockNFT(address) external view;

  function unlockNFT(address) external view;

  function transferNFT(address, address) external view;
}
