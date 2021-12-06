// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./oracles/interfaces/IPriceOracle.sol";
import "./governance/ProtocolParameters.sol";
import "./libraries/ReserveProposal.sol";
import "./libraries/Constants.sol";
import "./ReservesManager.sol";
import "./Structs.sol";

/**
 * @title the contract for buying and selling reserves
 * @dev the owner should be a governance contract because manage upgrades
 */
contract ReserveMarketplace is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ReserveProposal for SaleReserveProposal;
    using ReserveProposal for PurchaseReserveProposal;

    /// @notice the address of the protocol parameters contract controlled by governance
    ProtocolParameters public immutable protocol;

    /// @notice the address of the reserves manager contract hanlding the funds and the active reserves
    address public reservesManagerAddress;

    /// @dev the sale reserve proposal data structures
    mapping(bytes32 => SaleReserveProposal) private _saleReserveProposals;

    /// @dev the purchase reserve proposal data structures
    mapping(bytes32 => PurchaseReserveProposal) private _purchaseReserveProposals;

    /**
     * @dev emitted when a sale reserve is completed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param collateralToken the address of the ERC20 token that should be used for collateral
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     * @param reservePeriod the duration in seconds of the reserve
     */
    event SaleReserved(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer,
        uint256 reservePeriod
    );

    /**
     * @dev emitted when a sale reserve is proposed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param collateralToken the address of the ERC20 token that should be used for collateral
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     * @param reservePeriod the duration in seconds of the reserve
     * @param validityPeriod the duration in seconds of the proposal availability
     */
    event SaleReserveProposed(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        uint256 reservePeriod,
        uint256 validityPeriod
    );

    /**
     * @dev emitted when a sale reserve proposal is canceled
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param collateralToken the address of the ERC20 token that should be used for collateral
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     * @param reservePeriod the duration in seconds of the reserve
     */
    event SaleReserveProposalCanceled(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        uint256 reservePeriod
    );

    /**
     * @dev emitted when a purchase reserve is completed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param collateralToken the address of the ERC20 token that should be used for collateral
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     * @param reservePeriod the duration in seconds of the reserve
     */
    event PurchaseReserved(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer,
        uint256 reservePeriod
    );

    /**
     * @dev emitted when a purchase reserve is proposed
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param collateralToken the address of the ERC20 token that should be used for collateral
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     * @param reservePeriod the duration in seconds of the reserve
     * @param validityPeriod the duration in seconds of the proposal availability
     */
    event PurchaseReserveProposed(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        uint256 reservePeriod,
        uint256 validityPeriod
    );

    /**
     * @dev emitted when a purchase reserve proposal is canceled
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token that should be used for payment
     * @param collateralToken the address of the ERC20 token that should be used for collateral
     * @param price the amount of paymentToken that should be paid
     * @param collateralPercent the percent of the price as collateral
     * @param reservePeriod the duration in seconds of the reserve
     */
    event PurchaseReserveProposalCanceled(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        uint256 reservePeriod
    );

    /**
     * @dev the initializer modifier is to avoid someone initializing
     *      the implementation contract after deployment
     */
    constructor(address protocolParameters_) initializer {
        protocol = ProtocolParameters(protocolParameters_);
    }

    /**
     * @dev initializes the contract
     */
    function initialize(address reservesManagerAddress_) public initializer {
        reservesManagerAddress = reservesManagerAddress_;

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
     * @param collateralToken_ the address of the token to use for collateral
     * @param price_ the price of the sale proposal
     * @param collateralPercent_ the percent representing minimum collateral (to avoid liquidation by undercollateralization)
     * @param beneficiary_ the address receiving the payment tokens if the sale is executed
     * @param reservePeriod_ the duration in seconds of the reserve period if reserve is executed
     * @param validityPeriod_ the duration in seconds of the proposal availability
     * @param buyerToMatch_ the address to get the id for the match
     */
    function approveReserveToSell(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_,
        address beneficiary_,
        uint80 collateralPercent_,
        uint64 reservePeriod_,
        uint64 validityPeriod_,
        address buyerToMatch_
    ) external nonReentrant {
        // check if is the token owner
        require(IERC721(collection_).ownerOf(tokenId_) == msg.sender, "Only owner can approve");
        require(reservePeriod_ > protocol.minimumReservePeriod(), "Reserve period must be greater");

        // check collateral percent
        require(
            collateralPercent_ < 100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS,
            "Invalid collateral percent"
        );

        // not using encodePacked to avoid collisions
        bytes32 id = keccak256(
            abi.encode(
                collection_,
                tokenId_,
                paymentToken_,
                collateralToken_,
                price_,
                collateralPercent_,
                reservePeriod_,
                msg.sender
            )
        );

        // try to sell the reserve in the moment if possible
        if (buyerToMatch_ != address(0)) {
            bytes32 matchId = keccak256(
                abi.encode(
                    collection_,
                    tokenId_,
                    paymentToken_,
                    collateralToken_,
                    price_,
                    collateralPercent_,
                    reservePeriod_,
                    buyerToMatch_
                )
            );

            if (_purchaseReserveProposals[matchId].price > 0) {
                PurchaseReserveProposal memory purchaseProposal = _purchaseReserveProposals[matchId];

                // not allow undercollateralized proposals
                uint256 percentage = _getCollateralAmountPercent(
                    collateralToken_,
                    paymentToken_,
                    purchaseProposal.collateralInitialAmount,
                    price_
                );

                require(
                    percentage >= collateralPercent_,
                    "Attempt to accept an undercollateralized proposal"
                );

                // if the amount matches
                if (purchaseProposal.price == price_) {
                    // allowance can be not enough at this moment, or could have been canceled
                    if (purchaseProposal.tryToSellReserve(reservesManagerAddress)) {
                        delete _purchaseReserveProposals[matchId];

                        // save the struct with the reserve info
                        ReservesManager(reservesManagerAddress).startReserve(
                            collection_,
                            tokenId_,
                            paymentToken_,
                            collateralToken_,
                            price_,
                            collateralPercent_,
                            purchaseProposal.collateralInitialAmount,
                            reservePeriod_,
                            msg.sender,
                            purchaseProposal.buyer
                        );

                        emit SaleReserved(
                            collection_,
                            tokenId_,
                            paymentToken_,
                            collateralToken_,
                            price_,
                            collateralPercent_,
                            msg.sender,
                            purchaseProposal.buyer,
                            reservePeriod_
                        );
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
            collateralToken: collateralToken_,
            tokenId: tokenId_,
            owner: msg.sender,
            beneficiary: beneficiary_,
            price: price_,
            collateralPercent: collateralPercent_,
            reservePeriod: reservePeriod_,
            expirationTimestamp: uint64(block.timestamp + validityPeriod_) // solhint-disable-line not-rely-on-time
        });

        emit SaleReserveProposed(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            reservePeriod_,
            validityPeriod_
        );
    }

    /**
     * @notice allows to approve an intention of reserve purchase at a price with some collateral percent
     * @dev the reserve will be tried to be sold in the same transaction if a matching purchase reserve proposal is found
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param collateralToken_ the address of the token to use for collateral
     * @param price_ the price of the sale proposal
     * @param beneficiary_ the address receiving the payment tokens if the sale is executed
     * @param collateralPercent_ the percent representing minimum collateral (to avoid liquidation by undercollateralization)
     * @param collateralInitialAmount_ the initial amount of collateral deposited
     * @param reservePeriod_ the duration in seconds of the reserve period if reserve is executed
     * @param validityPeriod_ the duration in seconds of the proposal availability
     * @param sellerToMatch_ the address to get the id for the match
     */
    function approveReserveToBuy(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_,
        address beneficiary_,
        uint80 collateralPercent_,
        uint256 collateralInitialAmount_,
        uint64 reservePeriod_,
        uint64 validityPeriod_,
        address sellerToMatch_
    ) external nonReentrant {
        require(
            IERC20(paymentToken_).balanceOf(msg.sender) >=
                (price_ * collateralPercent_) / (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS),
            "Not enough balance to pay for collateral"
        );
        require(reservePeriod_ > protocol.minimumReservePeriod(), "Reserve period must be greater");

        // not using encodePacked to avoid collisions
        bytes32 id = keccak256(
            abi.encode(
                collection_,
                tokenId_,
                paymentToken_,
                collateralToken_,
                price_,
                collateralPercent_,
                reservePeriod_,
                msg.sender
            )
        );

        require(price_ > 0, "Price can't be 0");

        {
            // not allow undercollateralized proposals
            uint256 percentage = _getCollateralAmountPercent(
                collateralToken_,
                paymentToken_,
                collateralInitialAmount_,
                price_
            );

            require(percentage >= collateralPercent_, "Attempt to create an undercollateralized proposal");
        }

        // try to purchase the reserve in the moment if possible
        if (sellerToMatch_ != address(0)) {
            bytes32 matchId = keccak256(
                abi.encode(
                    collection_,
                    tokenId_,
                    paymentToken_,
                    collateralToken_,
                    price_,
                    collateralPercent_,
                    reservePeriod_,
                    sellerToMatch_
                )
            );

            if (_saleReserveProposals[matchId].price > 0) {
                SaleReserveProposal memory saleProposal = _saleReserveProposals[matchId];

                // if the amount matches
                if (saleProposal.price == price_) {
                    // allowance can be not enough at this moment, or could have been canceled
                    if (saleProposal.tryToBuyReserve(reservesManagerAddress, collateralInitialAmount_)) {
                        delete _saleReserveProposals[matchId];

                        // save the struct with the reserve info
                        ReservesManager(reservesManagerAddress).startReserve(
                            collection_,
                            tokenId_,
                            paymentToken_,
                            collateralToken_,
                            price_,
                            collateralPercent_,
                            collateralInitialAmount_,
                            reservePeriod_,
                            saleProposal.owner,
                            msg.sender
                        );

                        emit PurchaseReserved(
                            collection_,
                            tokenId_,
                            paymentToken_,
                            collateralToken_,
                            price_,
                            collateralPercent_,
                            saleProposal.owner,
                            msg.sender,
                            reservePeriod_
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
            collateralToken: collateralToken_,
            tokenId: tokenId_,
            buyer: msg.sender,
            beneficiary: beneficiary_,
            price: price_,
            collateralPercent: collateralPercent_,
            collateralInitialAmount: collateralInitialAmount_,
            reservePeriod: reservePeriod_,
            expirationTimestamp: uint64(block.timestamp + validityPeriod_) // solhint-disable-line not-rely-on-time
        });

        emit PurchaseReserveProposed(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            reservePeriod_,
            validityPeriod_
        );
    }

    /**
     * @notice allows to cancel a sale reserve proposal
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param collateralToken_ the address of the token to use for collateral
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing minimum collateral (to avoid liquidation by undercollateralization)
     * @param reservePeriod_ the duration in seconds of the reserve
     * @param owner_ the owner of the token
     */
    function cancelSaleReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_,
        uint80 collateralPercent_,
        uint64 reservePeriod_,
        address owner_
    ) external {
        (SaleReserveProposal memory proposal, bytes32 id) = getSaleReserveProposal(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            reservePeriod_,
            owner_
        );

        require(proposal.owner == msg.sender, "Only owner can cancel");

        delete _saleReserveProposals[id];

        emit SaleReserveProposalCanceled(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            reservePeriod_
        );
    }

    /**
     * @notice allows to cancel a purchase reserve proposal
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param collateralToken_ the address of the token to use for collateral
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing minimum collateral (to avoid liquidation by undercollateralization)
     * @param reservePeriod_ the duration in seconds of the reserve
     * @param buyer_ the buyer
     */
    function cancelPurchaseReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_,
        uint80 collateralPercent_,
        uint64 reservePeriod_,
        address buyer_
    ) external {
        (PurchaseReserveProposal memory proposal, bytes32 id) = getPurchaseReserveProposal(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            reservePeriod_,
            buyer_
        );

        require(proposal.buyer == msg.sender, "Only buyer can cancel");

        delete _purchaseReserveProposals[id];

        emit PurchaseReserveProposalCanceled(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            reservePeriod_
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
     * @param collateralToken_ the address of the token to use for collateral
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing minimum collateral (to avoid liquidation by undercollateralization)
     * @param reservePeriod_ the duration in seconds of the reserve
     * @param owner_ the owner of the token
     */
    function getSaleReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_,
        uint80 collateralPercent_,
        uint64 reservePeriod_,
        address owner_
    ) public view returns (SaleReserveProposal memory proposal, bytes32 id) {
        // not using encodePacked to avoid collisions
        id = keccak256(
            abi.encode(
                collection_,
                tokenId_,
                paymentToken_,
                collateralToken_,
                price_,
                collateralPercent_,
                reservePeriod_,
                owner_
            )
        );
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
     * @param collateralToken_ the address of the token to use for collateral
     * @param price_ the price of the proposal
     * @param collateralPercent_ the percent representing minimum collateral (to avoid liquidation by undercollateralization)
     * @param reservePeriod_ the duration in seconds of the reserve
     * @param buyer_ the buyer
     */
    function getPurchaseReserveProposal(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_,
        uint80 collateralPercent_,
        uint64 reservePeriod_,
        address buyer_
    ) public view returns (PurchaseReserveProposal memory proposal, bytes32 id) {
        // not using encodePacked to avoid collisions
        id = keccak256(
            abi.encode(
                collection_,
                tokenId_,
                paymentToken_,
                collateralToken_,
                price_,
                collateralPercent_,
                reservePeriod_,
                buyer_
            )
        );
        proposal = getPurchaseReserveProposalById(id);
    }

    /**
     * @dev helper to get the percentage representing the fraction of the value in USD from
     *      an amount of collateral to the price of a proposal
     */
    function _getCollateralAmountPercent(
        address collateralToken_,
        address paymentToken_,
        uint256 collateralAmount_,
        uint256 price_
    ) internal view returns (uint256 percentage) {
        IPriceOracle priceOracle = IPriceOracle(ReservesManager(reservesManagerAddress).priceOracle());

        // check undercollateralization with price oracle
        // cToken is the collateral token and pToken is the payment token
        uint256 cDecimals = IERC20Metadata(collateralToken_).decimals();
        uint256 pDecimals = IERC20Metadata(paymentToken_).decimals();

        // (price oracle return 6 decimals)
        uint256 cTokenToUSDPure = priceOracle.price(collateralToken_);
        uint256 pTokenToUSDPure = priceOracle.price(paymentToken_);

        uint256 collateralValue = collateralAmount_ * cTokenToUSDPure;
        uint256 reservePriceValue = price_ * pTokenToUSDPure;

        uint256 collateralValueScaled;
        // scale collateral value to reserve price value decimals
        if (cDecimals > pDecimals) {
            collateralValueScaled = collateralValue / 10**(cDecimals - pDecimals);
        } else {
            collateralValueScaled = collateralValue * 10**(pDecimals - cDecimals);
        }

        // get the current percent with decimals
        percentage =
            (collateralValueScaled * 100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS) /
            reservePriceValue;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
