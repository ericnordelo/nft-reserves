// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {INFTVault} from "./interface/INFTVault.sol";

contract NFTVault is INFTVault {
  constructor() public {
  }
  
  function owner(address) external view returns(address) {
    return address(0);
  }

  function lockNFT(address) external view {
  }

  function unlockNFT(address) external view {
  }

  function transferNFT(address, address) external view {
  }
}
