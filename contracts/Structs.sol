// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

struct SaleReserveProposal {
    address collection;
    uint256 tokenId;
    address paymentToken;
    address collateralToken;
    uint64 expirationTimestamp;
    uint256 price;
    uint80 collateralPercent;
    address owner;
    address beneficiary;
    uint64 reservePeriod;
}

struct PurchaseReserveProposal {
    address collection;
    uint256 tokenId;
    address paymentToken;
    address collateralToken;
    uint64 expirationTimestamp;
    uint256 price;
    uint256 collateralInitialAmount;
    uint80 collateralPercent;
    address buyer;
    address beneficiary;
    uint64 reservePeriod;
}

struct ActiveReserve {
    address collection;
    uint256 tokenId;
    uint64 reservePeriod;
    address seller;
    uint64 activationTimestamp;
    address buyer;
    address paymentToken;
    address collateralToken;
    uint80 collateralPercent;
    uint256 price;
}

struct ReserveAmounts {
    uint256 collateral;
    uint256 payment;
}
