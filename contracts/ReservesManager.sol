// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./governance/ProtocolParameters.sol";
import "./libraries/Constants.sol";
import "./ReserveMarketplace.sol";
import "./Structs.sol";

/**
 * @title contract managing the active reserves
 */
contract ReservesManager is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice the address of the reserves marketplace
    ReserveMarketplace public immutable marketplace;

    /// @notice the address of the protocol parameters contract controlled by governance
    ProtocolParameters public immutable protocol;

    /**
     * @notice the active reserves by id:
     *         Id = keccak256(collection, tokenId, sellerAddress, buyerAddress)
     */
    mapping(bytes32 => ActiveReserve) public activeReserves;

    /// @notice the amounts of tokens the active reserve has
    mapping(bytes32 => ReserveAmounts) public reserveAmounts;

    /**
     * @dev emitted when a reserve is canceled
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param collateralToken the address of the ERC20 token used for collateral
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     * @param executor the address who canceled
     */
    event ReserveCanceled(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer,
        address executor
    );

    /**
     * @dev emitted when the buyer pay the price in time
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param collateralToken the address of the ERC20 token used for collateral
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     */
    event ReservePricePaid(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer
    );

    /**
     * @dev emitted when reserve is succesfully liquidated (purchased)
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param collateralToken the address of the ERC20 token used for collateral
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     */
    event PurchaseExecuted(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer
    );

    /**
     * @dev emitted when reserve is liquidated without puchase (tokens claimed)
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param collateralToken the address of the ERC20 token used for collateral
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     */
    event PurchaseCanceled(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address collateralToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer
    );

    /**
     * @dev emitted when the collateral of a reserve is increased
     * @param reserveId the id of the active reserve
     * @param amount the amount to increase
     */
    event CollateralIncreased(bytes32 reserveId, uint256 amount);

    /**
     * @dev emitted when the collateral of a reserve is decreased
     * @param reserveId the id of the active reserve
     * @param amount the amount to decrease
     */
    event CollateralDecreased(bytes32 reserveId, uint256 amount);

    /**
     * @dev validates callability only from marketplace
     */
    modifier onlyMarketplace() {
        require(msg.sender == address(marketplace), "Only callable from the marketplace");
        _;
    }

    /**
     * @dev the initializer modifier is to avoid someone initializing
     *      the implementation contract after deployment
     */
    constructor(address marketplace_, address protocolParameters_) initializer {
        marketplace = ReserveMarketplace(marketplace_);
        protocol = ProtocolParameters(protocolParameters_);
    }

    /**
     * @dev initializes the contract
     */
    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @notice allows to cancel an active reserve paying the corresponding fees
     * @param activeReserveId_ the id of the reserve
     */
    function cancelReserve(bytes32 activeReserveId_) external nonReentrant {
        ActiveReserve memory reserve = activeReserves[activeReserveId_];

        require(reserve.price > 0, "Non-existent active proposal");

        // the reserve period should not be over
        require(
            reserve.reservePeriod + reserve.activationTimestamp > block.timestamp, // solhint-disable-line not-rely-on-time
            "Reserve expired. Pay or liquidate"
        );

        ReserveAmounts memory amounts = reserveAmounts[activeReserveId_];

        // check the caller and execute corresponding action
        if (msg.sender == reserve.seller) {
            _cancelFromSeller(
                amounts,
                reserve.collection,
                reserve.tokenId,
                reserve.buyer,
                reserve.paymentToken,
                reserve.collateralToken,
                reserve.price
            );
        } else if (msg.sender == reserve.buyer) {
            _cancelFromBuyer(
                amounts,
                reserve.collection,
                reserve.tokenId,
                reserve.buyer,
                reserve.paymentToken,
                reserve.collateralToken,
                reserve.price
            );
        } else {
            revert("Invalid caller. Should be buyer or seller");
        }

        // remove the reserve
        delete activeReserves[activeReserveId_];

        emit ReserveCanceled(
            reserve.collection,
            reserve.tokenId,
            reserve.paymentToken,
            reserve.collateralToken,
            reserve.price,
            reserve.collateralPercent,
            reserve.seller,
            reserve.buyer,
            msg.sender
        );
    }

    /**
     * @notice allows to liquidate the reserve after expiration, either
     *         executing the purchase if payment was made, or returning the token
     *         and the collateral
     *
     * @param activeReserveId_ the id of the reserve
     */
    function liquidateReserve(bytes32 activeReserveId_) external nonReentrant {
        ActiveReserve memory reserve = activeReserves[activeReserveId_];

        require(reserve.price > 0, "Non-existent active proposal");

        // check the caller and make corresponding validation
        if (msg.sender == reserve.seller) {
            // the reserve period and the buyer grace period should be over
            require(
                reserve.reservePeriod + reserve.activationTimestamp + protocol.buyerPurchaseGracePeriod() <
                    block.timestamp, // solhint-disable-line not-rely-on-time
                "Buyer period to pay not finished yet"
            );
        } else if (msg.sender == reserve.buyer) {
            // the reserve period should be over (the buyer grace period could be active)
            require(
                reserve.reservePeriod + reserve.activationTimestamp < block.timestamp, // solhint-disable-line not-rely-on-time
                "Reserve period not finished yet"
            );
        } else {
            revert("Invalid caller. Should be buyer or seller");
        }

        ReserveAmounts memory amounts = reserveAmounts[activeReserveId_];

        // if payment was made from buyer, execute the purchase
        if (amounts.payment == reserve.price) {
            _liquidatePaidReserve(
                amounts,
                reserve.collection,
                reserve.tokenId,
                reserve.price,
                reserve.paymentToken,
                reserve.collateralToken,
                reserve.collateralPercent,
                reserve.seller,
                reserve.buyer
            );
        } else {
            // if the payment wasn't made in time, return the token and the collateral to the seller
            _liquidateUnpaidReserve(
                amounts,
                reserve.collection,
                reserve.tokenId,
                reserve.price,
                reserve.paymentToken,
                reserve.collateralToken,
                reserve.collateralPercent,
                reserve.seller,
                reserve.buyer
            );
        }

        // remove the reserve
        delete activeReserves[activeReserveId_];
    }

    /**
     * @notice allows the buyer to pay the price amount
     *         (should be done before expiration and grace period)
     *
     * @param activeReserveId_ the id of the reserve
     */
    function payThePrice(bytes32 activeReserveId_) external {
        ActiveReserve memory reserve = activeReserves[activeReserveId_];

        require(msg.sender == reserve.buyer, "Only proposal buyer allowed");
        require(reserveAmounts[activeReserveId_].payment < reserve.price, "Already paid");
        require(
            reserve.reservePeriod + reserve.activationTimestamp + protocol.buyerPurchaseGracePeriod() >
                block.timestamp, // solhint-disable-line not-rely-on-time
            "Period to pay finished"
        );

        // update the state
        reserveAmounts[activeReserveId_].payment = reserve.price;

        // lock the price to the manager
        IERC20(reserve.paymentToken).safeTransferFrom(msg.sender, address(this), reserve.price);

        emit ReservePricePaid(
            reserve.collection,
            reserve.tokenId,
            reserve.paymentToken,
            reserve.collateralToken,
            reserve.price,
            reserve.collateralPercent,
            reserve.seller,
            reserve.buyer
        );
    }

    /**
     * @dev save the reserve to storage as active reserve
     * @param collection_ the address of the collection where the token belongs to
     * @param tokenId_ the id of the token to sell
     * @param paymentToken_ the address of the token to use for payment
     * @param price_ the price of the sale proposal
     * @param collateralPercent_ the percent representing the collateral
     * @param reservePeriod_ the duration in seconds of the reserve period if reserve is executed
     * @param seller_ the address of the seller
     * @param buyer_ the address of the buyer
     */
    function startReserve(
        address collection_,
        uint256 tokenId_,
        address paymentToken_,
        uint256 price_,
        uint80 collateralPercent_,
        uint64 reservePeriod_,
        address seller_,
        address buyer_
    ) external onlyMarketplace {
        // not using encodePacked to avoid collisions
        bytes32 reserveId = keccak256(abi.encode(collection_, tokenId_, seller_, buyer_));

        // save the struct with the reserve info
        activeReserves[reserveId] = ActiveReserve({
            collection: collection_,
            tokenId: tokenId_,
            seller: seller_,
            buyer: buyer_,
            paymentToken: paymentToken_,
            collateralToken: paymentToken_,
            collateralPercent: collateralPercent_,
            price: price_,
            reservePeriod: reservePeriod_,
            activationTimestamp: uint64(block.timestamp) // solhint-disable-line not-rely-on-time
        });

        uint256 minimumCollateral = (collateralPercent_ * price_) /
            (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS);

        reserveAmounts[reserveId].collateral = minimumCollateral;
    }

    /**
     * @notice allows the owner to increase the collateral amount in collateral token
     * @param activeReserveId_ the if of the corresponding active reserve
     * @param amount_ the amount to increase
     */
    function increaseReserveCollateral(bytes32 activeReserveId_, uint256 amount_) external {
        ActiveReserve memory reserve = activeReserves[activeReserveId_];

        require(reserve.price > 0, "Non-existent active reserve");
        require(msg.sender == reserve.buyer, "Only buyer allowed");

        ReserveAmounts memory amounts = reserveAmounts[activeReserveId_];
        require(amounts.payment < reserve.price, "Price already paid");

        // increment the collateral
        reserveAmounts[activeReserveId_].collateral = amounts.collateral + amount_;

        // get the funds in collateral token
        IERC20(reserve.collateralToken).safeTransferFrom(msg.sender, address(this), amount_);

        emit CollateralIncreased(activeReserveId_, amount_);
    }

    /**
     * @notice allows the owner to decrease the collateral amount in collateral token
     * @param activeReserveId_ the if of the corresponding active reserve
     * @param amount_ the amount to decrease
     */
    function decreaseReserveCollateral(bytes32 activeReserveId_, uint256 amount_) external {
        ActiveReserve memory reserve = activeReserves[activeReserveId_];

        require(reserve.price > 0, "Non-existent active reserve");
        require(msg.sender == reserve.buyer, "Only buyer allowed");

        ReserveAmounts memory amounts = reserveAmounts[activeReserveId_];

        // if is already paid collateral can be removed, then if not check undercollateralization
        if (amounts.payment < reserve.price) {
            // the amount left should be greater than or equal to the collateral percent
            uint256 minimumCollateral = (reserve.collateralPercent * reserve.price) /
                (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS);

            require(minimumCollateral <= amounts.collateral - amount_, "Attemp to uncollateralize reserve");
        } else {
            require(amounts.collateral >= amount_, "Insufficient amount for request");
        }

        // decrement the collateral
        reserveAmounts[activeReserveId_].collateral = amounts.collateral - amount_;

        // return the funds in collateral token
        IERC20(reserve.collateralToken).safeTransfer(msg.sender, amount_);

        emit CollateralDecreased(activeReserveId_, amount_);
    }

    /**
     * @dev helper to cancel from seller
     */
    function _cancelFromSeller(
        ReserveAmounts memory amounts_,
        address collection_,
        uint256 tokenId_,
        address buyer_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_
    ) internal {
        uint256 cancelFee = (price_ * protocol.sellerCancelFeePercent()) / 100;

        // return the collateral plus the seller cancel fee to the buyer
        IERC20(paymentToken_).safeTransferFrom(msg.sender, buyer_, cancelFee);
        require(IERC20(collateralToken_).transfer(buyer_, amounts_.collateral), "Fail to transfer");

        // return the payment if was made
        if (amounts_.payment > 0) {
            require(IERC20(paymentToken_).transfer(buyer_, amounts_.payment), "Fail to transfer");
        }

        // now return the token to the seller
        IERC721(collection_).transferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     * @dev helper to cancel from buyer
     */
    function _cancelFromBuyer(
        ReserveAmounts memory amounts_,
        address collection_,
        uint256 tokenId_,
        address seller_,
        address paymentToken_,
        address collateralToken_,
        uint256 price_
    ) internal {
        uint256 cancelFee = (price_ * protocol.buyerCancelFeePercent()) / 100;

        // return the token plus the buyer cancel fee to the seller
        IERC20(paymentToken_).safeTransferFrom(msg.sender, seller_, cancelFee);
        IERC721(collection_).transferFrom(address(this), seller_, tokenId_);

        // now return the collateral to the buyer
        IERC20(collateralToken_).safeTransfer(msg.sender, amounts_.collateral);

        // return the payment if was made
        if (amounts_.payment > 0) {
            IERC20(paymentToken_).safeTransfer(msg.sender, amounts_.payment);
        }
    }

    /**
     * @dev helper for liquidations
     */
    function _liquidatePaidReserve(
        ReserveAmounts memory amounts_,
        address collection_,
        uint256 tokenId_,
        uint256 price_,
        address paymentToken_,
        address collateralToken_,
        uint80 collateralPercent_,
        address seller_,
        address buyer_
    ) internal {
        // transfer the corresponding funds
        IERC20(paymentToken_).safeTransfer(seller_, amounts_.payment);

        // return the collateral
        IERC20(collateralToken_).safeTransfer(buyer_, amounts_.collateral);

        // transfer the NFT
        IERC721(collection_).transferFrom(address(this), buyer_, tokenId_);

        emit PurchaseExecuted(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            seller_,
            buyer_
        );
    }

    /**
     * @dev helper for liquidations
     */
    function _liquidateUnpaidReserve(
        ReserveAmounts memory amounts_,
        address collection_,
        uint256 tokenId_,
        uint256 price_,
        address paymentToken_,
        address collateralToken_,
        uint80 collateralPercent_,
        address seller_,
        address buyer_
    ) internal {
        // transfer the collateral
        IERC20(collateralToken_).safeTransfer(seller_, amounts_.collateral);

        // transfer the NFT
        IERC721(collection_).transferFrom(address(this), seller_, tokenId_);

        emit PurchaseCanceled(
            collection_,
            tokenId_,
            paymentToken_,
            collateralToken_,
            price_,
            collateralPercent_,
            seller_,
            buyer_
        );
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
