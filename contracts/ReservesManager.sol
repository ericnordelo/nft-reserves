// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./governance/ProtocolParameters.sol";
import "./libraries/Constants.sol";
import "./ReserveMarketplace.sol";
import "./Structs.sol";

/**
 * @title contract managing the active reserves
 */
contract ReservesManager is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice the address of the reserves marketplace
    ReserveMarketplace public immutable marketplace;

    /// @notice the address of the protocol parameters contract controlled by governance
    ProtocolParameters public immutable protocol;

    /**
     * @dev emitted when a reserve is canceled
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
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
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer,
        address executor
    );

    /**
     * @dev emitted when a purchase is executed in the grace period
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     */
    event PurchaseExecuted(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer
    );

    /**
     * @dev emitted when a purchase is executed in the grace period
     * @param collection the address of the NFT collection contract
     * @param tokenId the id of the NFT
     * @param paymentToken the address of the ERC20 token used for payment
     * @param price the amount of paymentToken used for payment
     * @param collateralPercent the percent of the price as collateral
     * @param seller the address of the seller
     * @param buyer the address of the buyer
     */
    event ReserveClaimed(
        address collection,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 collateralPercent,
        address seller,
        address buyer
    );

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
        (
            address collection,
            uint256 tokenId,
            uint64 reservePeriod,
            address seller,
            uint64 activationTimestamp,
            address buyer,
            address paymentToken,
            uint80 collateralPercent,
            uint256 price
        ) = marketplace.activeReserves(activeReserveId_);

        require(price > 0, "Non-existent active proposal");

        // the reserve period should not be over
        require(
            reservePeriod + activationTimestamp > block.timestamp, // solhint-disable-line not-rely-on-time
            "Reserve expired. Pay or claim"
        );

        // check the caller and execute corresponding action
        if (msg.sender == seller) {
            _cancelFromSeller(collection, tokenId, buyer, paymentToken, collateralPercent, price);
        } else if (msg.sender == buyer) {
            _cancelFromBuyer(collection, tokenId, seller, paymentToken, collateralPercent, price);
        } else {
            revert("Invalid caller. Should be buyer or seller");
        }

        // remove the reserve
        marketplace.removeActiveReserve(activeReserveId_);

        emit ReserveCanceled(
            collection,
            tokenId,
            paymentToken,
            price,
            collateralPercent,
            seller,
            buyer,
            msg.sender
        );
    }

    /**
     * @notice allows to execute a purchase when the reserve period finishes (within the buyer period of grace)
     * @param activeReserveId_ the id of the reserve
     */
    function executePurchase(bytes32 activeReserveId_) external nonReentrant {
        (
            address collection,
            uint256 tokenId,
            uint64 reservePeriod,
            address seller,
            uint64 activationTimestamp,
            address buyer,
            address paymentToken,
            uint80 collateralPercent,
            uint256 price
        ) = marketplace.activeReserves(activeReserveId_);

        require(price > 0, "Non-existent active proposal");
        require(msg.sender == buyer, "Only the buyer can execute the purchase");

        // the reserve period should be over and the buyer grace period active
        require(
            reservePeriod + activationTimestamp < block.timestamp, // solhint-disable-line not-rely-on-time
            "Reserve period not finished yet"
        );
        require(
            reservePeriod + activationTimestamp + protocol.buyerPurchaseGracePeriod() > block.timestamp, // solhint-disable-line not-rely-on-time
            "Grace period finished"
        );

        // transfer the corresponding funds
        uint256 collateral = (collateralPercent * price) / (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS);

        // transfer the rest of the funds to reach the price
        require(
            IERC20(paymentToken).transferFrom(msg.sender, seller, price - collateral),
            "Fail to transfer"
        );

        // transfer the collateral
        require(IERC20(paymentToken).transferFrom(address(this), seller, collateral), "Fail to transfer");

        // transfer the NFT
        IERC721(collection).transferFrom(address(this), buyer, tokenId);

        // remove the reserve
        marketplace.removeActiveReserve(activeReserveId_);

        emit PurchaseExecuted(collection, tokenId, paymentToken, price, collateralPercent, seller, buyer);
    }

    /**
     * @notice allows a seller to get his token back, and the collateral, when
     *         the buyer fails to pay after reserve period and buyer grace period
     *
     * @param activeReserveId_ the id of the reserve
     */
    function retrieveTokenAndCollateral(bytes32 activeReserveId_) external nonReentrant {
        (
            address collection,
            uint256 tokenId,
            uint64 reservePeriod,
            address seller,
            uint64 activationTimestamp,
            address buyer,
            address paymentToken,
            uint80 collateralPercent,
            uint256 price
        ) = marketplace.activeReserves(activeReserveId_);

        require(price > 0, "Non-existent active proposal");
        require(msg.sender == seller, "Only the seller can claim");

        // the reserve period and the buyer grace period should be over
        require(
            reservePeriod + activationTimestamp + protocol.buyerPurchaseGracePeriod() < block.timestamp, // solhint-disable-line not-rely-on-time
            "Grace period not finished yet"
        );

        // transfer the corresponding funds
        uint256 collateral = (collateralPercent * price) / (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS);

        // transfer the collateral
        require(IERC20(paymentToken).transferFrom(address(this), seller, collateral), "Fail to transfer");

        // transfer the NFT
        IERC721(collection).transferFrom(address(this), seller, tokenId);

        // remove the reserve
        marketplace.removeActiveReserve(activeReserveId_);

        emit ReserveClaimed(collection, tokenId, paymentToken, price, collateralPercent, seller, buyer);
    }

    /**
     * @dev helper to cancel from seller
     */
    function _cancelFromSeller(
        address collection_,
        uint256 tokenId_,
        address buyer_,
        address paymentToken_,
        uint80 collateralPercent_,
        uint256 price_
    ) internal {
        uint256 cancelFee = (price_ * protocol.sellerCancelFeePercent()) / 100;
        uint256 collateral = (collateralPercent_ * price_) /
            (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS);

        // return the collateral plus the seller cancel fee to the buyer
        require(IERC20(paymentToken_).transferFrom(msg.sender, buyer_, cancelFee), "Fail to transfer");
        require(IERC20(paymentToken_).transferFrom(address(this), buyer_, collateral), "Fail to transfer");

        // now return the token to the seller
        IERC721(collection_).transferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     * @dev helper to cancel from buyer
     */
    function _cancelFromBuyer(
        address collection_,
        uint256 tokenId_,
        address seller_,
        address paymentToken_,
        uint80 collateralPercent_,
        uint256 price_
    ) internal {
        uint256 cancelFee = (price_ * protocol.buyerCancelFeePercent()) / 100;
        uint256 collateral = (collateralPercent_ * price_) /
            (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS);

        // return the token plus the buyer cancel fee to the seller
        require(IERC20(paymentToken_).transferFrom(msg.sender, seller_, cancelFee), "Fail to transfer");
        IERC721(collection_).transferFrom(address(this), seller_, tokenId_);

        // now return the collateral to the buyer
        require(
            IERC20(paymentToken_).transferFrom(address(this), msg.sender, collateral),
            "Fail to transfer"
        );
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
