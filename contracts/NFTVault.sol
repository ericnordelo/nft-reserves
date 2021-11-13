// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {INFTVault} from "./interface/INFTVault.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFTVault is INFTVault {
  address admin;
  mapping(address => mapping(uint256 => address)) lockedNFTOwner;
  constructor(address _admin) public {
    admin = _admin;
  }
  
  function owner(address nft, uint256 nftID) external returns(address) {
    return IERC721(nft).ownerOf(nftID);
  }

  function lockNFT(address nft, uint256 nftID) external {
    address owner = IERC721(nft).ownerOf(nftID);
    IERC721(nft).transferFrom(owner, admin, nftID);
    lockedNFTOwner[nft][nftID] = owner;
  }

  function unlockNFT(address nft, uint256 nftID) external {
    address owner = lockedNFTOwner[nft][nftID];
    require(owner != address(0), "not locked NFT");
    IERC721(nft).transferFrom(admin, owner, nftID);
    delete lockedNFTOwner[nft][nftID];
  }

  function transferNFT(address nft, uint256 nftID, address to) external {
    address owner = lockedNFTOwner[nft][nftID];
    require(owner != address(0), "not locked NFT");
    IERC721(nft).transferFrom(admin, to, nftID);
    delete lockedNFTOwner[nft][nftID];
  }
}
