// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Structs.sol";

/**
 * @title the vault holding the assets
 * @dev the owner should be a governance contract because manage upgrades
 */
contract NFTVault is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice the decimals of the collateral percent
    uint256 public constant COLLATERAL_PERCENT_DECIMALS = 2;

    /// @dev the reserve sale proposal data structures
    mapping(bytes32 => ReserveSaleProposal) private _reserveSaleProposals;

    /// @dev the reserve purchase proposal data structures
    mapping(bytes32 => ReservePurchaseProposal) private _reservePurchaseProposals;

    /**
     * @dev emitted when a reserve sale is completed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     */
    event ReserveSaleCompleted(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

    /**
     * @dev emitted when a reserve sale is proposed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     */
    event ReserveSaleProposed(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

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
        __ReentrancyGuard_init();
    }

    /**
     * @notice allows to approve an intention of sale at a price
     * @dev the token will be tried to be sold in the same transaction if a matching purchase proposal is found
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the sale proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param beneficiary_ the address receiving the payment tokens if the sale is executed
     * @param buyerToMatch_ the address to get the id for the match
     */
    function approveReserveToSell(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        address beneficiary_,
        uint80 collateralPercent_,
        address buyerToMatch_
    ) external nonReentrant {
        // check if is the token owner
        require(IERC721(collection_).ownerOf(tokenId_) == msg.sender, "Only owner can approve");

        // check collateral percent
        require(collateralPercent_ < 100 * 10**COLLATERAL_PERCENT_DECIMALS, "Invalid collateral percent");

        // not using encodePacked to avoid collisions
        bytes32 id = keccak256(
            abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, msg.sender)
        );

        // try to sell it in the moment if possible
        if (buyerToMatch_ != address(0)) {
            bytes32 matchId = keccak256(
                abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, buyerToMatch_)
            );

            if (_reservePurchaseProposals[matchId].price > 0) {
                ReservePurchaseProposal memory purchaseProposal = _reservePurchaseProposals[matchId];

                // if the amount is enough
                if (purchaseProposal.price >= price_) {
                    // allowance can't be enough at this moment, or could have been canceled
                    if (_tryToSellReserve(purchaseProposal)) {
                        delete _reservePurchaseProposals[matchId];

                        // if there was a previous SaleProposal delete it, because the sale was already executed
                        if (_reserveSaleProposals[id].collection != address(0)) {
                            delete _reserveSaleProposals[id];
                        }

                        emit ReserveSaleCompleted(
                            collection_,
                            tokenId_,
                            paymentToken_,
                            price_,
                            collateralPercent_
                        );
                        return;
                    } else {
                        // the proposal has not the right allowance, so has to be removed
                        delete _reservePurchaseProposals[id];
                    }
                }
            }
        }

        // if automatic sale couldn't be done
        _reserveSaleProposals[id] = ReserveSaleProposal({
            collection: collection_,
            paymentToken: paymentToken_,
            tokenId: tokenId_,
            owner: msg.sender,
            beneficiary: beneficiary_,
            price: price_,
            collateralPercent: collateralPercent_
        });

        emit ReserveSaleProposed(collection_, tokenId_, paymentToken_, price_, collateralPercent_);
    }

    /**
     * @dev helper for trying to automatically sell a reserve sale proposal
     *      tranferring the collateral and the NFT
     */
    function _tryToSellReserve(ReservePurchaseProposal memory purchaseProposal_) private returns (bool sold) {
        // try to make the transfer from the buyer (the collateral)
        try
            IERC20(purchaseProposal_.paymentToken).transferFrom(
                purchaseProposal_.buyer,
                address(this),
                (purchaseProposal_.collateralPercent * purchaseProposal_.price) /
                    (100 * 10**COLLATERAL_PERCENT_DECIMALS)
            )
        returns (bool success) {
            if (!success) {
                return false;
            }
        } catch {
            return false;
        }

        // if the previous transfer was successfull transfer the NFT
        IERC721(purchaseProposal_.collection).transferFrom(
            msg.sender,
            address(this),
            purchaseProposal_.tokenId
        );

        sold = true;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
