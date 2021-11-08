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

/*
OWNER:
-  Whitelist asset to be open to receive Reserval Offers. He may (start with his own initial offer). IMPORTANT: if the owner sets an offer you get only the approval of the Owner ffor the NFT to the contract but the NFT is NOT LOCKED at this stage
-  Owner can remove from whitelist without any cost as long as no offer has been accepted first.
-  Owner can accept an offer. At this stage NFT is locked on the contract
-  (modified, can't withdraw) Owner can withdraw collateral deposited by the buyer at any moment
-  If owner wants to cancel the Reserval (Reserval), he needs to payback what he withdrawn +a fee
BUYER:
-  Buyer can set offers for whitelisted NFTs. IMPORTANT: the offer does not lock the collateral of the buyer. It only gets the proposal for that toekns aand amoiunt to the contrract. For example if i propose 10K SHIB, I approve the contract but i do not lock them.
-  Buyer can reserve NFT directly if the owner has some offer
-  Buyer needs to keep a level of collateral. Otherwise can be liquidaated and lose it.
-  If collateral goes below the ratio, buyer needs to deposit more collateral.
-  At future (expiration) the buyer needs to pay the Reserve Price within a period of 5 days max. If not, he loses the Reserval of buying
*/

contract NFTReservalManager {
  using StructuredLinkedList for StructuredLinkedList.List;
  uint256 private constant PCT_DIVIDER = 100000;

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
  
  event CollateralDepost(
    uint256 offerID,
    address token,
    uint256 amount,
    bool isDeposit
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
      _putInCollateral(offer.colTokens[i], offer.buyer, offer.colAmounts[i]);
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
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);
    require(msg.sender == reserval.owner, "Not owner of reserval");

    //_processAssign(true);

    emit Assigned(true, offer.reservalID, offerID);
  }

  function payReserve(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);
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
      _putInCollateral(token, token, amount);
    }
    offer.colAmounts[id] += amount;

    emit CollateralDepost(offerID, token, amount, true);
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

    emit CollateralDepost(offerID, token, amount, false);
  }

  function getNFTReservals(address owner) external returns (uint256[] memory reservalIDs) {

  }

  function getOffers(address buyer) external returns (uint256[] memory offerIDs) {

  }

  function getOfferReqs(address owner) external returns (uint256[] memory offerIDs) {

  }

  function checkAssign() external {
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
