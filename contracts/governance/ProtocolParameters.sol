// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title parameters controlled by governance
 * @notice the owner of this contract should be the
 *         timelock controller of the governance feature
 */
contract ProtocolParameters is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice minimum duration in seconds of a reserve
    uint256 public minimumReservePeriod;

    /// @notice the percent of the price the seller has to pay for cancelling a reserve
    uint256 public sellerCancelFeePercent;

    /// @notice the percent of the price the buyer has to pay for cancelling a reserve
    uint256 public buyerCancelFeePercent;

    /// @notice the period when the buyer is able to execute the purchase
    uint256 public buyerPurchaseGracePeriod;

    event MinimumReservePeriodUpdated(uint256 from, uint256 to);
    event SellerCancelFeePercentUpdated(uint256 from, uint256 to);
    event BuyerCancelFeePercentUpdated(uint256 from, uint256 to);
    event BuyerPurchaseGracePeriodUpdated(uint256 from, uint256 to);

    /**
     * @dev the initializer modifier is to avoid someone initializing
     *      the implementation contract after deployment
     */
    constructor() initializer {} // solhint-disable-line no-empty-blocks

    /**
     * @dev initializes the contract,
     *      sets the default (initial) values of the parameters
     *      and also transfers the ownership to the governance
     */
    function initialize(
        uint256 minimumReservePeriod_,
        uint256 sellerCancelFeePercent_,
        uint256 buyerCancelFeePercent_,
        uint256 buyerPurchaseGracePeriod_,
        address governanceContractAddress_
    ) public initializer {
        require(minimumReservePeriod_ > 0, "Invalid minimum reserve period");
        minimumReservePeriod = minimumReservePeriod_;

        require(sellerCancelFeePercent_ < 100, "Invalid seller cancel fee percent");
        sellerCancelFeePercent = sellerCancelFeePercent_;

        require(sellerCancelFeePercent_ < 100, "Invalid buyer cancel fee percent");
        buyerCancelFeePercent = buyerCancelFeePercent_;

        require(buyerPurchaseGracePeriod_ >= 15 minutes, "Invalid buyer puchase grace period");
        buyerPurchaseGracePeriod = buyerPurchaseGracePeriod_;

        __Ownable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        transferOwnership(governanceContractAddress_);
    }

    function setMinimumReservePeriod(uint256 minimumReservePeriod_) external onlyOwner {
        require(minimumReservePeriod_ > 0, "Invalid minimum reserve period");
        emit MinimumReservePeriodUpdated(minimumReservePeriod, minimumReservePeriod_);
        minimumReservePeriod = minimumReservePeriod_;
    }

    function setSellerCancelFeePercent(uint256 sellerCancelFeePercent_) external onlyOwner {
        require(sellerCancelFeePercent_ < 100, "Invalid seller cancel fee percent");
        emit SellerCancelFeePercentUpdated(sellerCancelFeePercent, sellerCancelFeePercent_);
        sellerCancelFeePercent = sellerCancelFeePercent_;
    }

    function setBuyerCancelFeePercent(uint256 buyerCancelFeePercent_) external onlyOwner {
        require(buyerCancelFeePercent_ < 100, "Invalid buyer cancel fee percent");
        emit BuyerCancelFeePercentUpdated(buyerCancelFeePercent, buyerCancelFeePercent_);
        buyerCancelFeePercent = buyerCancelFeePercent_;
    }

    function setBuyerPurchaseGracePeriod(uint256 buyerPurchaseGracePeriod_) external onlyOwner {
        require(buyerPurchaseGracePeriod_ >= 15 minutes, "Invalid buyer puchase grace period");
        emit BuyerPurchaseGracePeriodUpdated(buyerPurchaseGracePeriod, buyerPurchaseGracePeriod_);
        buyerPurchaseGracePeriod = buyerPurchaseGracePeriod_;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
