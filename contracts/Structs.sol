// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

struct ReserveSaleProposal {
    address collection;
    uint256 tokenId;
    address paymentToken;
    uint256 price;
    uint80 collateralPercent;
    address owner;
    address beneficiary;
}

struct ReservePurchaseProposal {
    address collection;
    uint256 tokenId;
    address paymentToken;
    uint256 price;
    uint80 collateralPercent;
    address buyer;
    address beneficiary;
}
