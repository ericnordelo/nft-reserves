// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "solidity-linked-list/contracts/StructuredLinkedList.sol";
import {IPriceOracle} from "./interface/IPriceOracle.sol";
import {NFTVault} from "./NFTVault.sol";


contract NFTReservalManager {
  using StructuredLinkedList for StructuredLinkedList.List;
  uint256 private constant PCT_DIVIDER = 100000;
  bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

  event OReservalCreated(
    address owner,
    address nft,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct,
    uint256 reservalID
  );

  event OReservalCanceled(
    address owner,
    uint256 reservalID
  );

  event BOfferCreated(
    address buyer,
    uint256 reservalID,
    address nft,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct,
    uint256 offerID
  );

  event OOfferAccepted(
    uint256 offerID
  );

  event Assigned(
    bool assigned,
    uint256 reservalID,
    uint256 offerID
  );
  
  event CollateralDeposit(
    uint256 offerID,
    address token,
    uint256 amount,
    bool isDeposit
  );

  event ReservePayed(
    uint256 offerID
  );
  
  struct NFTReserval {
    address owner;
    address nft;
    uint256 expiry;
    address token;
    uint256 price;
    uint256 pct;
    uint256 reservalID;
    uint256 acceptedOfferID;
  }

  struct Offer {
    address buyer;
    uint256 reservalID;
    address nft;
    uint256 expiry;
    address token;
    uint256 price;
    uint256 pct;
    address[] colTokens;
    uint256[] colAmounts;
    uint256 offerID;
    bool accepted;
    bool reservePayed;
  }

  uint256 cntReserval;
  uint256 cntOffer;
  address[] tokens;
  uint256 TOKEN_CNT;
  address nftVault;
  address priceOracle;
  address admin;

  mapping(uint256 => NFTReserval) reservals;
  mapping(uint256 => Offer) offers;

  mapping(address => bool) validToken;

  mapping(address => StructuredLinkedList.List) listReserval;
  mapping(address => StructuredLinkedList.List) listOffer;
  mapping(uint256 => StructuredLinkedList.List) listOfferReq;

  constructor(
    address[] memory _tokens,
    address _nftVault,
    address _priceOracle
  ) public {
    tokens = _tokens;
    nftVault = _nftVault;
    priceOracle = _priceOracle;
    admin = address(this);
    TOKEN_CNT = _tokens.length;
    for (uint i = 0; i < TOKEN_CNT; i++) {
        validToken[_tokens[i]] = true;
    }
    cntReserval = 0;
    cntOffer = 0;
  }
  
  function createReserval(
    address nft,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct
  ) external returns (uint256 reservalID) {
    require(msg.sender == _nftOwner(nft), "Not Owner of NFT");
    cntReserval++;
    reservalID = cntReserval;
    NFTReserval memory reserval = NFTReserval(msg.sender, nft, expiry, token, price, pct, reservalID, 0);

    _reserval_add(reserval.owner, reservalID);
    reservals[reservalID] = reserval;
    
    emit OReservalCreated(reserval.owner, nft, expiry, token, price, pct, reservalID);
  }
  
  function cancelReserval(
    uint256 reservalID
  ) external {
    NFTReserval storage reserval = _getReserval(reservalID);
    require(reserval.owner != address(0), "No such reserval exists");
    require(reserval.owner == msg.sender, "Not owner of reserval");

    _reserval_remove(reserval.owner, reservalID);
    delete reservals[reservalID];
    
    emit OReservalCanceled(reserval.owner, reservalID);
  }
  
  function createOffer(
    uint256 reservalID
  ) external returns (uint256 offerID) {
    NFTReserval storage reserval = _getReserval(reservalID);
    require(reserval.owner != address(0), "No such reserval exists");

    cntOffer++;
    offerID = cntOffer;
    address[] memory colTokens = new address[](TOKEN_CNT);
    uint256[] memory colAmounts = new uint256[](TOKEN_CNT);

    Offer memory offer = Offer(
      msg.sender,
      reservalID,
      reserval.nft,
      reserval.expiry,
      reserval.token,
      reserval.price,
      reserval.pct,
      colTokens,
      colAmounts,
      offerID,
      false,
      false
      );

    emit BOfferCreated(
      offer.buyer,
      reservalID,
      reserval.nft,
      reserval.expiry,
      reserval.token,
      reserval.price,
      reserval.pct,
      offerID
      );
  }

  function acceptOffer(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);
    require(msg.sender == reserval.owner, "Not owner of reserval");
    
    require(!offer.accepted, "The offer is already accepted");
    require(reserval.acceptedOfferID == 0, "The reserval is already matched");

    require(_checkCollateral(offer), "Not enough collateral");
    require(_checkAllowance(offer), "Not allowed enough");
    for (uint i = 0; i < offer.colTokens.length; i++) {
      _putInCollateral(offer.buyer, offer.colTokens[i], offer.colAmounts[i]);
    }
    _lockNFT(reserval.nft);

    reserval.acceptedOfferID = offerID;
    offer.accepted = true;

    emit OOfferAccepted(offerID);
  }

  function assignOffer(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    require(offer.accepted, "Not accepted offer");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);
    require(msg.sender == reserval.owner, "Not owner of reserval");

    if (offer.reservePayed) {
      _safeTransfer(reserval.token, reserval.owner, reserval.price);
      _transferNFT(reserval.nft, reserval.owner, offer.buyer);
    }
    else {
      uint256 unpayed = _tokenToUSD(offer.token) * offer.price * offer.pct / PCT_DIVIDER;
      for (uint i = 0; i < offer.colTokens.length; i++) {
        uint256 amountToOwner = unpayed / _tokenToUSD(offer.colTokens[i]);
        if (amountToOwner > offer.colAmounts[i]) amountToOwner = offer.colAmounts[i];
        uint256 amountToBuyer = offer.colAmounts[i] - amountToOwner;
        if (amountToOwner > 0) {
          unpayed = unpayed - _tokenToUSD(offer.colTokens[i]) * amountToOwner;
          _safeTransfer(offer.colTokens[i], reserval.owner, amountToOwner);
        }
        if (amountToBuyer > 0) {
          _safeTransfer(offer.colTokens[i], offer.buyer, amountToBuyer);
        }
      }
    }

    _reserval_remove(reserval.owner, reserval.reservalID);
    _offer_remove(offer.buyer, offerID);
    emit Assigned(offer.reservePayed, offer.reservalID, offerID);

    delete offers[offerID];
    delete reservals[reserval.reservalID];

  }

  function payReserve(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    require(offer.accepted, "Not accepted offer");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);

    offer.reservePayed = true;

    emit ReservePayed(offerID);
  }

  function depositCollateral(
    uint256 offerID,
    address token,
    uint256 amount
  ) external {
    require(validToken[token], "Not vaild token");
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    require(msg.sender == offer.buyer, "Not buyer of offer");
    require(offer.accepted, "Not accepted offer");

    require(amount > 0, "INSUFFICIENT_INPUT_AMOUNT");

    uint id = 0;
    for (id = 0; id < offer.colTokens.length; id++) {
      if (offer.colTokens[id] == token) break;
    }
    if (offer.colTokens.length == id) {
      offer.colTokens.push(token);
      offer.colAmounts.push(0);
    }
    if (offer.accepted) {
      _putInCollateral(offer.buyer, token, amount);
    }
    offer.colAmounts[id] += amount;

    emit CollateralDeposit(offerID, token, amount, true);
  }

  function withdrawCollateral(
    uint256 offerID,
    address token,
    uint256 amount
  ) external {
    require(validToken[token], "Not vaild token");
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    require(msg.sender == offer.buyer, "Not buyer of offer");
    require(offer.accepted, "Not accepted offer");

    require(amount > 0, "INSUFFICIENT_INPUT_AMOUNT");
    
    uint id = 0;
    for (id = 0; id < offer.colTokens.length; id++) {
      if (offer.colTokens[id] == token) break;
    }
    require((offer.colTokens.length > id) && (offer.colAmounts[id] >= amount), "Not enough amount deposited");

    if (offer.accepted) {
      _putOutCollateral(token, msg.sender, amount);
    }
    offer.colAmounts[id] -= amount;

    emit CollateralDeposit(offerID, token, amount, false);
  }

  function getNFTReservals(address owner) external returns (uint256[] memory reservalIDs) {

  }

  function getOffers(address buyer) external returns (uint256[] memory offerIDs) {

  }

  function getOfferReqs(address owner) external returns (uint256[] memory offerIDs) {

  }

  function checkAssign() external {
  }

  function getReserval(uint256 reservalID) external returns (NFTReserval memory reserval) {
    NFTReserval storage _reserval = _getReserval(reservalID);
    require(_reserval.owner != address(0), "No such reserval exists");
    reserval = _reserval;
  }

  function getOffer(uint256 offerID) external returns (Offer memory offer) {
    Offer storage _offer = _getOffer(offerID);
    require(_offer.buyer != address(0), "No such offer exists");
    offer = _offer;
  }

  function _getReserval(uint256 reservalID) private returns (NFTReserval storage) {
    return reservals[reservalID];
  }

  function _getOffer(uint256 offerID) private returns (Offer storage) {
    return offers[offerID];
  }

  function _nftOwner(address nft) private returns (address) {
    // not completed yet

    return address(0);
  }

  function _lockNFT(address nft) private {
    // not completed yet
  }

  function _transferNFT(address nft, address from, address to) private {
    // not completed yet
  }

  function _tokenToUSD(address token) private returns (uint256) {
    // not completed yet
    return IPriceOracle(priceOracle).price(token);
  }

  function _checkCollateral(Offer storage offer) private returns (bool) {
    uint256 totalUSD = 0;
    for (uint i = 0; i < offer.colTokens.length; i++) {
      totalUSD = _tokenToUSD(offer.colTokens[i]) * offer.colAmounts[i];
    }
    uint256 requiredUSD = _tokenToUSD(offer.token) * offer.price * offer.pct / PCT_DIVIDER;
    return requiredUSD <= totalUSD;
  }

  function _checkAllowance(Offer storage offer) private returns (bool) {
    uint256 totalUSD = 0;
    for (uint i = 0; i < offer.colTokens.length; i++) {
      uint256 allownce = IERC20(offer.colTokens[i]).allowance(offer.buyer, admin);
      if (allownce < offer.colAmounts[i]) return false;
    }
    return true;
  }

  function _putInCollateral(address account, address token, uint256 amount) private {
    IERC20(token).transferFrom(account, admin, amount);
  }

  function _putOutCollateral(address account, address token, uint256 amount) private {
    IERC20(token).transferFrom(admin, account, amount);
  }

  function _safeTransfer(
      address token,
      address to,
      uint value
  ) private {
      (bool success, bytes memory data) = token.call(
          abi.encodeWithSelector(SELECTOR, to, value)
      );
      require(
          success && (data.length == 0 || abi.decode(data, (bool))),
          "AMM: TRANSFER_FAILED"
      );
  }

  //-------------------------------------------------------------------------------//
  //--------------------------- Linked List functions -----------------------------//
  //-------------------------------------------------------------------------------//
  function _reserval_add(address owner, uint256 reservalID) private {
    StructuredLinkedList.pushBack(listReserval[owner], reservalID);
  }

  function _reserval_remove(address owner, uint256 reservalID) private {
    StructuredLinkedList.remove(listReserval[owner], reservalID);
  }

  function _offer_add(address buyer, uint256 offerID) private {
    StructuredLinkedList.pushBack(listOffer[buyer], offerID);
  }

  function _offer_remove(address buyer, uint256 offerID) private {
    StructuredLinkedList.remove(listOffer[buyer], offerID);
  }

  function _offerReq_add(uint256 reservalID, uint256 offerID) private {
    StructuredLinkedList.pushBack(listOfferReq[reservalID], offerID);
  }

  function _offerReq_remove(uint256 reservalID, uint256 offerID) private {
    StructuredLinkedList.remove(listOfferReq[reservalID], offerID);
  }
  //-------------------------------------------------------------------------------//
}
