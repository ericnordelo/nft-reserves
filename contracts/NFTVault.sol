// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title the vault holding the assets
 * @dev the owner should be a governance contract because manage upgrades
 */
contract NFTVault is UUPSUpgradeable, OwnableUpgradeable {
    mapping(address => mapping(uint256 => address)) private _lockedNFTOwner;

    /**
     * @dev the initializer modifier is to avoid someone initializing
     *      the implementation contract after deployment
     */
    constructor() initializer {} // solhint-disable-line no-empty-blocks

    /**
     * @dev initializes the contract
     */
    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    // function lockNFT(address nft, uint256 nftID) external {
    //     address owner_ = IERC721(nft).ownerOf(nftID);
    //     IERC721(nft).transferFrom(owner_, admin, nftID);
    //     _lockedNFTOwner[nft][nftID] = owner_;
    // }

    // function unlockNFT(address nft, uint256 nftID) external {
    //     address owner_ = _lockedNFTOwner[nft][nftID];
    //     require(owner_ != address(0), "not locked NFT");
    //     IERC721(nft).transferFrom(admin, owner_, nftID);
    //     delete _lockedNFTOwner[nft][nftID];
    // }

    // function transferNFT(
    //     address nft,
    //     uint256 nftID,
    //     address to
    // ) external {
    //     address owner_ = _lockedNFTOwner[nft][nftID];
    //     require(owner_ != address(0), "not locked NFT");
    //     IERC721(nft).transferFrom(admin, to, nftID);
    //     delete _lockedNFTOwner[nft][nftID];
    // }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
