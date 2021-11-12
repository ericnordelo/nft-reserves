// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {INFTVault} from "./interface/INFTVault.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFTVault is INFTVault {
  constructor() public {
  }
  
  function owner(address nft) external view returns(address) {
    return IERC721(nft).owner
  }

  function lockNFT(address nft) external view {
  }

  function unlockNFT(address nft) external view {
  }

  function transferNFT(address nft, address to) external view {
  }
}
