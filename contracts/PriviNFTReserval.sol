// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

contract PriviNFTReserval {
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
    address token,
    address price,
    uint256 reservalID,
    uint256 offerID
  );

  event OOfferAccepted(
    address owner,
    address buyer,
    uint256 reservalID,
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
  }

  struct Offer {
    address buyer;
    address owner;
    uint256 reservalID;
    uint256 offerID;
  }

  uint256 counter;
  address[] tokens;
  address nftPool;
  address priceOracle;
  address admin;

  mapping(uint256 => NFTReserval) reservals;
  mapping(address => mapping (address => uint256)) reserves;
  mapping(address => bool) validToken;

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
  }
  
  function createReserval(
    address nft,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct
  ) external returns (uint256 reservalID) {
    require(msg.sender == _nftOwner(nft), "Not Owner of NFT");
    reservalID = counter;
    counter++;
    NFTReserval memory reserval = NFTReserval(msg.sender, nft, expiry, token, price, pct, reservalID);
    reservals[reservalID] = reserval;
    
    emit OReservalCreated(msg.sender, nft, expiry, token, price, pct, reservalID);
  }
  
  function cancelReserval(
    uint256 reservalID
  ) external {
    NFTReserval storage reserval = _getReserval(reservalID);
    require(reserval.owner != address(0), "No such reserval exists");
    require(reserval.owner == msg.sender, "Not owner of reserval");

    delete reservals[reservalID];
    emit OReservalCanceled(msg.sender, reservalID);
  }
  
  function createOffer(
    uint256 reservalID
  ) external {
  }

  function acceptOffer(
    uint256 offerID
  ) external {
  }

  function assignOffer(
    uint256 offerID
  ) external {
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

  function _getReserval(uint256 reservalID) private returns (NFTReserval storage) {
    return reservals[reservalID];
  }

  function _nftOwner(address nft) private returns (address) {
    // not completed yet

    return address(0);
  }

  function _tokenToUSD(address token) private returns (uint256) {
    // not completed yet
    return IPriceOracle(priceOracle).price(token);
  }
}
