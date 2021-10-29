// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPriceOracle} from "./interface/IPriceOracle.sol";

/*
- person holds an NFT, may want to sell it. Set it into sale with conditions. The NFT is locked
  Future time when this will be sold
  Price at which it will be sold
  Pct of collateral required by the buyer to get this option of buying
- buyers can come there and make accept that by giving the collateral and adquiring that option of buying it. Lets make them receive an NFT which will be that option to buying and can be tradeable
- buyers can make their counterproposal, with the 3 parameters 1,2,3 before.
- owner can withdraw the NFT if not buyer came yet.
- owner can withdraw and use the collateral whenever he wants.
- owner can recover the NFT during that period by repaying the collateral he withdraw + some fee as penalty
- buyer can deposit collateral with different tokens (for example with ETH, DAI.. or maybe even JOTs)
- buyer needs to deposit more collateral if the LTV goes below the pct collateral required
- If it goes bellow, he gots liquidated and lose the option off buying.
*/

contract PriviNFTBuying {
  event OOptionCreated(
    address owner,
    address nft,
    uint256 expiry,
    uint256 price,
    uint256 pct,
    uint256 optionID
  );

  event OOptionCanceled(
    address owner,
    uint256 optionID
  );

  event BOfferCreated(
    address buyer,
    address token,
    address price,
    uint256 optionID,
    uint256 offerID
  );

  event OOfferAccepted(
    address owner,
    address buyer,
    uint256 optionID,
    uint256 offerID
  );

  event Assigned(
    bool assigned,
    uint256 optionID,
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
  
  struct NFTOption {
    address owner;
    address nft;
    uint256 expiry;
    uint256 pct;
    uint256 optionID;
  }

  struct Offer {
    address buyer;
    address owner;
    uint256 optionID;
    uint256 offerID;
  }

  uint256 counter;
  address[] tokens;
  address nftPool;
  address priceOracle;
  address admin;

  mapping(uint256 => NFTOption) options;
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
  
  function createOption(
    address nft,
    uint256 expiry,
    address token,
    uint256 price,
    uint256 pct
  ) external returns (uint256 optionID) {
    require(msg.sender == _nftOwner(nft), "Not Owner of NFT");
    optionID = counter;
    counter++;
    NFTOption memory option = NFTOption(msg.sender, nft, expiry, pct, optionID);
    options[optionID] = option;
    emit OOptionCreated(msg.sender, nft, expiry, price, pct, optionID);
  }

  function moidfyOption(
    uint256 optionID,
    address nft,
    uint256 expiry,
    uint256 price,
    uint256 pct
  ) external {
  }
  
  function cancelOption(
    uint256 optionID
  ) external {
    NFTOption storage option = _getOption(optionID);
    require(option.owner != address(0), "No such option exists");
    require(option.owner == msg.sender, "Not owner of option");

    delete options[optionID];
    emit OOptionCanceled(msg.sender, optionID);
  }
  
  function createOffer(
    uint256 optionID
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

  function _getOption(uint256 optionID) private returns (NFTOption storage) {
    return options[optionID];
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
