// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {INFTVault} from "./interface/INFTVault.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFTVault is INFTVault {
    address public admin;
    mapping(address => mapping(uint256 => address)) private _lockedNFTOwner;

    constructor(address _admin) {
        admin = _admin;
    }

    function owner(address nft, uint256 nftID) external view returns (address) {
        return IERC721(nft).ownerOf(nftID);
    }

    function lockNFT(address nft, uint256 nftID) external {
        address owner_ = IERC721(nft).ownerOf(nftID);
        IERC721(nft).transferFrom(owner_, admin, nftID);
        _lockedNFTOwner[nft][nftID] = owner_;
    }

    function unlockNFT(address nft, uint256 nftID) external {
        address owner_ = _lockedNFTOwner[nft][nftID];
        require(owner_ != address(0), "not locked NFT");
        IERC721(nft).transferFrom(admin, owner_, nftID);
        delete _lockedNFTOwner[nft][nftID];
    }

    function transferNFT(
        address nft,
        uint256 nftID,
        address to
    ) external {
        address owner_ = _lockedNFTOwner[nft][nftID];
        require(owner_ != address(0), "not locked NFT");
        IERC721(nft).transferFrom(admin, to, nftID);
        delete _lockedNFTOwner[nft][nftID];
    }
}
