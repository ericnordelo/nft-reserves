// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

struct SaleReserveProposal {
    address collection;
    uint256 tokenId;
    address paymentToken;
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
    uint256 price;
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
    address buyer;
    address paymentToken;
    uint80 collateralPercent;
    uint256 price;
}
