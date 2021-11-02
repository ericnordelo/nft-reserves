// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "solidity-linked-list/contracts/StructuredLinkedList.sol";
import {IPriceOracle} from "./interface/IPriceOracle.sol";

/*
OWNER:
-  Whitelist asset to be open to receive Reserval Offers. He may (start with his own initial offer). IMPORTANT: if the owner sets an offer you get only the approval of the Owner ffor the NFT to the contract but the NFT is NOT LOCKED at this stage
-  Owner can remove from whitelist without any cost as long as no offer has been accepted first.
-  Owner can accept an offer. At this stage NFT is locked on the contract
-  Owner can withdraw collateral deposited by the buyer at any moment
-  If owner wants to cancel the Reserval (Reserval), he needs to payback what he withdrawn +a fee
BUYER:
-  Buyer can set offers for whitelisted NFTs. IMPORTANT: the offer does not lock the collateraal of the buyer. It only gets the proposal for that toekns aand amoiunt to the contrract. For example if i propose 10K SHIB, I approve the contract but i do not lock them.
-  Buyer can reserve NFT directly if the owner has some offer
-  Buyer needs to keep a level of collateral. Otherwise can be liquidaated and lose it.
-  If collateral goes below the ratio, buyer needs to deposit more collateral.
-  At future (expiration) the buyer needs to pay the Reserve Price within a period of 5 days max. If not, he loses the Reserval of buying
*/

contract NFTReservalManager {
  using StructuredLinkedList for StructuredLinkedList.List;

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
  
  event Deposit(
    address account,
    address token,
    uint256 amount
  );

  event Withdraw(
    address account,
    address token,
    uint256 amount
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
    uint256 offerID;
    bool accepted;
  }

  uint256 cntReserval;
  uint256 cntOffer;
  address[] tokens;
  address nftPool;
  address priceOracle;
  address admin;

  mapping(uint256 => NFTReserval) reservals;
  mapping(uint256 => Offer) offers;

  mapping(address => mapping (address => uint256)) reserves;
  mapping(address => bool) validToken;

  mapping(address => StructuredLinkedList.List) listReserval;
  mapping(address => StructuredLinkedList.List) listOffer;
  mapping(uint256 => StructuredLinkedList.List) listOfferReq;

  constructor(
    address[] memory _tokens,
    address _nftPool,
    address _priceOracle
  ) public {
    tokens = _tokens;
    nftPool = _nftPool;
    priceOracle = _priceOracle;
    admin = address(this);
    for (uint i = 0; i < _tokens.length; i++) {
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
    Offer memory offer = Offer(msg.sender, reservalID, offerID, false);

    emit BOfferCreated(offer.buyer, reservalID, offerID);
  }

  function acceptOffer(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);
    require(msg.sender == reserval.owner, "Not owner of reserval");

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

  function unassignOffer(
    uint256 offerID
  ) external {
    Offer storage offer = _getOffer(offerID);
    require(offer.buyer != address(0), "No such offer exists");
    
    NFTReserval storage reserval = _getReserval(offer.reservalID);
    require(msg.sender == reserval.owner, "Not owner of reserval");

    //_processAssign(false);

    emit Assigned(false, offer.reservalID, offerID);
  }

  function deposit(
    address token,
    uint256 amount
  ) external {
    require(amount > 0, "INSUFFICIENT_INPUT_AMOUNT");
    IERC20(token).transferFrom(msg.sender, admin, amount);
    reserves[msg.sender][token] = reserves[msg.sender][token] + amount;

    emit Deposit(msg.sender, token, amount);
  }

  function withdraw(
    address token,
    uint256 amount
  ) external {
    require(amount > 0, "INSUFFICIENT_INPUT_AMOUNT");

    require(reserves[msg.sender][token] >= amount, "Not enough asset");
    IERC20(token).transferFrom(admin, msg.sender, amount);
    reserves[msg.sender][token] = reserves[msg.sender][token] - amount;

    emit Withdraw(msg.sender, token, amount);
  }

  function recover(
  ) external {
  }

  function totalAssetUSD(
    address user
  ) external returns (uint256) {
    uint256 total = 0;
    for (uint i = 0; i < tokens.length; i++) {
      total += reserves[user][tokens[i]];
    }
    return total;
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
