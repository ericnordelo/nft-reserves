// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "solidity-linked-list/contracts/StructuredLinkedList.sol";
import {IPriceOracle} from "./interface/IPriceOracle.sol";
import {INFTVault} from "./interface/INFTVault.sol";
import {NFTVault} from "./NFTVault.sol";


contract NFTReservalManager {
  using StructuredLinkedList for StructuredLinkedList.List;
  uint256 private constant PCT_DIVIDER = 100000;
  bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

  event EReservalUpdated(
    address owner,
    address nft,
    uint256 nftID,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct,
    uint256 reservalID
  );

  event EReservalCanceled(
    address owner,
    uint256 reservalID
  );

  event EOfferUpdated(
    address buyer,
    uint256 reservalID,
    address nft,
    uint256 nftID,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct,
    uint256 offerID
  );

  event EOfferCanceled(
    address buyer,
    uint256 offerID
  );

  event EOfferAccepted(
    uint256 offerID
  );

  event EAssigned(
    bool assigned,
    uint256 reservalID,
    uint256 offerID
  );
  
  event ECollateralDeposit(
    uint256 offerID,
    address token,
    uint256 amount,
    bool isDeposit
  );

  event EReservePayed(
    uint256 offerID
  );
  
  struct NFTReserval {
    address owner;
    address nft;
    uint256 nftID;
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
    uint256 nftID;
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
    address _priceOracle
  ) public {
    tokens = new address[](0);
    admin = address(this);
    nftVault = address(new NFTVault(admin));
    priceOracle = _priceOracle;
    cntReserval = 0;
    cntOffer = 0;
  }

  function registerValidToken(
    address[] memory _tokens
  ) external {
    tokens = _tokens;
    TOKEN_CNT = _tokens.length;
    for (uint i = 0; i < TOKEN_CNT; i++) {
        validToken[_tokens[i]] = true;
    }
  }
  
  function updateReserval(
    address nft,
    uint256 nftID,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct,
    uint256 id
  ) external returns (uint256 reservalID) {
    require(msg.sender == _nftOwner(nft, nftID), "Not Owner of NFT");
    if (id != 0) {
      reservalID = id;
      NFTReserval storage reserval = _getReserval(reservalID);
      require(reserval.owner != address(0), "No such reserval exists");
      require(reserval.owner == msg.sender, "Not owner of reserval");

      _reserval_remove(reserval.owner, reservalID);
      delete reservals[reservalID];
    }
    else {
      cntReserval++;
      reservalID = cntReserval;
    }
    NFTReserval memory _reserval = NFTReserval(msg.sender, nft, nftID, expiry, token, price, pct, reservalID, 0);
    _reserval_add(_reserval.owner, reservalID);
    reservals[reservalID] = _reserval;
    
    emit EReservalUpdated(_reserval.owner, nft, nftID, expiry, token, price, pct, reservalID);
  }
  
  function cancelReserval(
    uint256 reservalID
  ) external {
    NFTReserval storage reserval = _getReserval(reservalID);
    require(reserval.owner != address(0), "No such reserval exists");
    require(reserval.owner == msg.sender, "Not owner of reserval");

    _reserval_remove(reserval.owner, reservalID);
    delete reservals[reservalID];
    
    emit EReservalCanceled(msg.sender, reservalID);
  }
  
  function updateOffer(
    uint256 reservalID,
    address nft,
    uint256 nftID,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct,
    uint256 id
  ) external returns (uint256 offerID) {
    if (id != 0) {
      offerID = id;
      Offer storage offer = _getOffer(offerID);
      require(offer.buyer != address(0), "No such offer exists");
      require(offer.buyer == msg.sender, "Not buyer of offer");

      _offer_remove(offer.buyer, offerID);
      _offerReq_remove(offer.reservalID, offerID);
      delete offers[offerID];
    }
    else {
      cntOffer++;
      offerID = cntOffer;
    }

    NFTReserval storage reserval = _getReserval(reservalID);
    require(reserval.owner != address(0), "No such reserval exists");
    require(reserval.nft == nft, "NFT is not matched");
    require(reserval.nftID == nftID, "NFT tokenID is not matched");

    address[] memory colTokens = new address[](TOKEN_CNT);
    uint256[] memory colAmounts = new uint256[](TOKEN_CNT);

    Offer memory _offer = Offer(
      msg.sender,
      reservalID,
      nft,
      nftID,
      expiry,
      token,
      price,
      pct,
      colTokens,
      colAmounts,
      offerID,
      false,
      false
      );

    offers[offerID] = _offer;
    _offerReq_add(reservalID, offerID);
    _offer_add(_offer.buyer, offerID);

    emit EOfferUpdated(
      _offer.buyer,
      reservalID,
      nft,
      nftID,
      expiry,
      token,
      price,
      pct,
      offerID
      );
  }

  function cancelOffer(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    require(offer.buyer == msg.sender, "Not buyer of offer");

    require(!offer.accepted, "Offer is already accepted");

    _offer_remove(offer.buyer, offerID);
    _offerReq_remove(offer.reservalID, offerID);
    delete offers[offerID];

    emit EOfferCanceled(msg.sender, offerID);
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
      _putIn(offer.buyer, offer.colTokens[i], offer.colAmounts[i]);
    }
    _lockNFT(offer.nft, offer.nftID);

    reserval.acceptedOfferID = offerID;
    offer.accepted = true;

    emit EOfferAccepted(offerID);
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
      _putOut(reserval.owner, offer.token, offer.price);
      _transferNFT(offer.nft, offer.nftID, offer.buyer);
    }
    else {
      uint256 unpayed = _tokenToUSD(offer.token) * offer.price * offer.pct / PCT_DIVIDER;
      for (uint i = 0; i < offer.colTokens.length; i++) {
        uint256 amountToOwner = unpayed / _tokenToUSD(offer.colTokens[i]);
        if (amountToOwner > offer.colAmounts[i]) amountToOwner = offer.colAmounts[i];
        uint256 amountToBuyer = offer.colAmounts[i] - amountToOwner;
        if (amountToOwner > 0) {
          unpayed = unpayed - _tokenToUSD(offer.colTokens[i]) * amountToOwner;
          _putOut(reserval.owner, offer.colTokens[i], amountToOwner);
        }
        if (amountToBuyer > 0) {
          _putOut(offer.buyer, offer.colTokens[i], amountToBuyer);
        }
      }
    }

    _reserval_remove(reserval.owner, reserval.reservalID);
    _offer_remove(offer.buyer, offerID);
    _offerReq_remove(offer.reservalID, offerID);
    emit EAssigned(offer.reservePayed, offer.reservalID, offerID);

    delete offers[offerID];
    delete reservals[reserval.reservalID];
  }

  function payReserve(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    require(offer.accepted, "Not accepted offer");
    require(!offer.reservePayed, "Already payReserved");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);

    _putIn(offer.buyer, offer.token, offer.price);
    for (uint i = 0; i < offer.colTokens.length; i++) {
      _putOut(offer.buyer, offer.colTokens[i], offer.colAmounts[i]);
    }

    offer.reservePayed = true;

    emit EReservePayed(offerID);
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
      _putIn(offer.buyer, token, amount);
    }
    offer.colAmounts[id] += amount;

    emit ECollateralDeposit(offerID, token, amount, true);
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
      _putOut(msg.sender, token, amount);
    }
    offer.colAmounts[id] -= amount;

    emit ECollateralDeposit(offerID, token, amount, false);
  }

  function getNFTReservals(address owner) external returns (uint256[] memory) {
    return _getFullList(listReserval[owner]);
  }

  function getOffers(address buyer) external returns (uint256[] memory) {
    return _getFullList(listOffer[buyer]);
  }

  function getOfferReqs(uint256 reservalID) external returns (uint256[] memory) {
    return _getFullList(listOfferReq[reservalID]);
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

  //-------------------------------------------------------------------------------//
  //----------------------------- private functions -------------------------------//
  //-------------------------------------------------------------------------------//
  function _getReserval(uint256 reservalID) private returns (NFTReserval storage) {
    return reservals[reservalID];
  }

  function _getOffer(uint256 offerID) private returns (Offer storage) {
    return offers[offerID];
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

  function _putIn(address account, address token, uint256 amount) private {
    IERC20(token).transferFrom(account, admin, amount);
  }

  function _putOut(address account, address token, uint256 amount) private {
    (bool success, bytes memory data) = token.call(
        abi.encodeWithSelector(SELECTOR, account, amount)
    );
    require(
        success && (data.length == 0 || abi.decode(data, (bool))),
        "AMM: TRANSFER_FAILED"
    );
  }
  //-------------------------------------------------------------------------------//


  //-------------------------------------------------------------------------------//
  //---------------------------- Interface functions ------------------------------//
  //-------------------------------------------------------------------------------//
  function _nftOwner(address nft, uint256 nftID) private returns (address) {
    return INFTVault(nftVault).owner(nft, nftID);
  }

  function _lockNFT(address nft, uint256 nftID) private {
    INFTVault(nftVault).lockNFT(nft, nftID);
  }

  function _unlockNFT(address nft, uint256 nftID) private {
    INFTVault(nftVault).unlockNFT(nft, nftID);
  }

  function _transferNFT(address nft, uint256 nftID, address to) private {
    INFTVault(nftVault).transferNFT(nft, nftID, to);
  }

  function _tokenToUSD(address token) private returns (uint256) {
    return IPriceOracle(priceOracle).price(token);
  }
  //-------------------------------------------------------------------------------//


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

  function _getFullList(StructuredLinkedList.List storage list) private returns (uint256[] memory) {
    uint256[] memory ids = new uint256[](list.size);
    uint cnt = 0;
    for (uint256 cur = 0; ; ) {
      bool exists = true;
      (exists, cur) = StructuredLinkedList.getNextNode(list, cur);
      if (exists) {
        ids[cnt] = cur;
        cnt++;
      }
      else {
        break;
      }
    }
    return ids;
  }
  //-------------------------------------------------------------------------------//
}
