// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/ReserveProposal.sol";
import "./Structs.sol";

/**
 * @title the vault holding the assets
 * @dev the owner should be a governance contract because manage upgrades
 */
contract NFTVault is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ReserveProposal for SaleReserveProposal;
    using ReserveProposal for PurchaseReserveProposal;

    /// @notice the decimals of the collateral percent
    uint256 public constant COLLATERAL_PERCENT_DECIMALS = 2;

    /// @dev the sale reserve proposal data structures
    mapping(bytes32 => SaleReserveProposal) private _saleReserveProposals;

    /// @dev the purchase reserve proposal data structures
    mapping(bytes32 => PurchaseReserveProposal) private _purchaseReserveProposals;

    /**
     * @notice the active reserves by id:
     *         Id = keccak256(collection, tokenId, sellerAddress, buyerAddress)
     */
    mapping(bytes32 => ActiveReserve) public activeReserves;

    /**
     * @dev emitted when a sale reserve is completed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     */
    event SaleReserved(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

    /**
     * @dev emitted when a sale reserve is proposed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     */
    event SaleReserveProposed(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

    /**
     * @dev emitted when a sale reserve proposal is canceled
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     */
    event SaleReserveProposalCanceled(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

    /**
     * @dev emitted when a purchase reserve is completed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     */
    event PurchaseReserved(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

    /**
     * @dev emitted when a purchase reserve is proposed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     */
    event PurchaseReserveProposed(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent
    );

    /**
     * @dev emitted when a purchase reserve proposal is canceled
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     */
    event PurchaseReserveProposalCanceled(
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
     * @notice allows to approve an intention of reserve sale at a price with some collateral percent
     * @dev the reserve will be tried to be sold in the same transaction if a matching purchase reserve proposal is found
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

        // try to sell the reserve in the moment if possible
        if (buyerToMatch_ != address(0)) {
            bytes32 matchId = keccak256(
                abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, buyerToMatch_)
            );

            if (_purchaseReserveProposals[matchId].price > 0) {
                PurchaseReserveProposal memory purchaseProposal = _purchaseReserveProposals[matchId];

                // if the amount is enough
                if (purchaseProposal.price >= price_) {
                    // allowance can't be enough at this moment, or could have been canceled
                    if (purchaseProposal.tryToSellReserve()) {
                        delete _purchaseReserveProposals[matchId];

                        // if there was a previous SaleProposal delete it, because the sale was already executed
                        if (_saleReserveProposals[id].collection != address(0)) {
                            delete _saleReserveProposals[id];
                        }

                        // not using encodePacked to avoid collisions
                        bytes32 reserveId = keccak256(
                            abi.encode(collection_, tokenId_, msg.sender, purchaseProposal.buyer)
                        );

                        //safe the struct with the reserve info
                        activeReserves[reserveId] = ActiveReserve({
                            collection: collection_,
                            tokenId: tokenId_,
                            seller: msg.sender,
                            buyer: purchaseProposal.buyer,
                            paymentToken: paymentToken_,
                            collateralPercent: collateralPercent_,
                            price: price_
                        });

                        emit SaleReserved(collection_, tokenId_, paymentToken_, price_, collateralPercent_);
                        return;
                    } else {
                        // the proposal has not the right allowance, so has to be removed
                        delete _purchaseReserveProposals[id];
                    }
                }
            }
        }

        // if automatic sale reserve couldn't be done
        _saleReserveProposals[id] = SaleReserveProposal({
            collection: collection_,
            paymentToken: paymentToken_,
            tokenId: tokenId_,
            owner: msg.sender,
            beneficiary: beneficiary_,
            price: price_,
            collateralPercent: collateralPercent_
        });

        emit SaleReserveProposed(collection_, tokenId_, paymentToken_, price_, collateralPercent_);
    }

    /**
     * @notice allows to approve an intention of reserve purchase at a price with some collateral percent
     * @dev the reserve will be tried to be sold in the same transaction if a matching purchase reserve proposal is found
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the sale proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param beneficiary_ the address receiving the payment tokens if the sale is executed
     * @param sellerToMatch_ the address to get the id for the match
     */
    function approvePurchase(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        uint80 collateralPercent_,
        address beneficiary_,
        address sellerToMatch_
    ) external nonReentrant {
        require(IERC20(paymentToken_).balanceOf(msg.sender) >= price_, "Not enough balance");

        // not using encodePacked to avoid collisions
        bytes32 id = keccak256(
            abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, msg.sender)
        );

        require(price_ > 0, "Price can't be 0");

        // try to purchase the reserve in the moment if possible
        if (sellerToMatch_ != address(0)) {
            bytes32 matchId = keccak256(
                abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, sellerToMatch_)
            );

            if (_saleReserveProposals[matchId].price > 0) {
                SaleReserveProposal memory saleProposal = _saleReserveProposals[matchId];

                // if the amount is enough
                if (saleProposal.price <= price_) {
                    // allowance can't be enough at this moment, or could have been canceled
                    if (saleProposal.tryToBuyReserve()) {
                        delete _saleReserveProposals[matchId];

                        // if there was another PurchaseProposal keep it

                        emit PurchaseReserved(
                            collection_,
                            tokenId_,
                            paymentToken_,
                            price_,
                            collateralPercent_
                        );
                        return;
                    } else {
                        // the proposal has not the right allowance, so has to be removed
                        delete _saleReserveProposals[matchId];
                    }
                }
            }
        }

        // if automatic sale couldn't be done
        _purchaseReserveProposals[id] = PurchaseReserveProposal({
            collection: collection_,
            paymentToken: paymentToken_,
            tokenId: tokenId_,
            buyer: msg.sender,
            beneficiary: beneficiary_,
            price: price_,
            collateralPercent: collateralPercent_
        });

        emit PurchaseReserveProposed(collection_, tokenId_, paymentToken_, price_, collateralPercent_);
    }

    /**
     * @notice allows to cancel a sale reserve proposal
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param owner_ the owner of the token
     */
    function cancelSaleReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        uint80 collateralPercent_,
        address owner_
    ) external {
        (SaleReserveProposal memory proposal, bytes32 id) = getSaleReserveProposal(
            collection_,
            tokenId_,
            paymentToken_,
            price_,
            collateralPercent_,
            owner_
        );

        require(proposal.owner == msg.sender, "Only owner can cancel");

        delete _saleReserveProposals[id];

        emit SaleReserveProposalCanceled(collection_, tokenId_, paymentToken_, price_, collateralPercent_);
    }

    /**
     * @notice allows to cancel a purchase reserve proposal
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param buyer_ the buyer
     */
    function cancelPurchaseReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        uint80 collateralPercent_,
        address buyer_
    ) external {
        (PurchaseReserveProposal memory proposal, bytes32 id) = getPurchaseReserveProposal(
            collection_,
            tokenId_,
            paymentToken_,
            price_,
            collateralPercent_,
            buyer_
        );

        require(proposal.buyer == msg.sender, "Only buyer can cancel");

        delete _purchaseReserveProposals[id];

        emit PurchaseReserveProposalCanceled(
            collection_,
            tokenId_,
            paymentToken_,
            price_,
            collateralPercent_
        );
    }

    /**
     * @notice getter to consult a sale reserve proposal definition by id
     * @param id_ the id of the proposal (keccak256 hash of the params)
     */
    function getSaleReserveProposalById(bytes32 id_)
        public
        view
        returns (SaleReserveProposal memory proposal)
    {
        require(_saleReserveProposals[id_].price > 0, "Non-existent proposal");
        proposal = _saleReserveProposals[id_];
    }

    /**
     * @notice getter to consult a sale proposal definition
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param owner_ the owner of the token
     */
    function getSaleReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        uint80 collateralPercent_,
        address owner_
    ) public view returns (SaleReserveProposal memory proposal, bytes32 id) {
        // not using encodePacked to avoid collisions
        id = keccak256(abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, owner_));
        proposal = getSaleReserveProposalById(id);
    }

    /**
     * @notice getter to consult a purchase reserve proposal definition by id
     * @param id_ the id of the proposal (keccak256 hash of the params)
     */
    function getPurchaseReserveProposalById(bytes32 id_)
        public
        view
        returns (PurchaseReserveProposal memory proposal)
    {
        require(_purchaseReserveProposals[id_].price > 0, "Non-existent proposal");
        proposal = _purchaseReserveProposals[id_];
    }

    /**
     * @notice getter to consult a purchase proposal definition
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param buyer_ the buyer
     */
    function getPurchaseReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        uint80 collateralPercent_,
        address buyer_
    ) public view returns (PurchaseReserveProposal memory proposal, bytes32 id) {
        // not using encodePacked to avoid collisions
        id = keccak256(abi.encode(collection_, tokenId_, paymentToken_, price_, collateralPercent_, buyer_));
        proposal = getPurchaseReserveProposalById(id);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
