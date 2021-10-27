// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PriviNFTBuying {
  event OptionCreated(
    address owner,
    address nft,
    uint256 expiry,
    uint256 price,
    uint256 pct,
    uint256 optionID
  );

  event OptionCanceled(
    address owner,
    uint256 optionID
  );

  event OptionSold(
    address owner,
    address buyer,
    uint256 optionID
  );

  event Depoist(
    address owner,
    address token,
    uint256 amount
  );

  event Withdraw(
    address owner,
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

  uint256 counter;

  mapping(uint256 => NFTOption) options;

  constructor(
    address token
  ) public {
  }
  
  function createOption(
    address nft,
    uint256 expiry,
    uint256 price,
    uint256 pct
  ) external returns (uint256 optionID) {
    require(msg.sender == _nftOwner(nft), "Not Owner of NFT");
    optionID = counter;
    counter++;
    NFTOption memory option = NFTOption(msg.sender, nft, expiry, pct, optionID);
    options[optionID] = option;
    emit OptionCreated(msg.sender, nft, expiry, price, pct, optionID);
  }
  
  function cancelOption(
    uint256 optionID
  ) external {
    NFTOption storage option = _getOption(optionID);
    require(option.owner != address(0), "No such option exists");
    require(option.owner == msg.sender, "Not owner of option");

    delete options[optionID];
    emit OptionCanceled(msg.sender, optionID);
  }

  function buyOption(
    uint256 optionID
  ) external {
    NFTOption storage option = _getOption(optionID);
    require(option.owner != address(0), "No such option exists");

  }

  function deposit(
    address token,
    uint256 amount
  ) external {
  }

  function withdraw(
    address token,
    uint256 amount
  ) external {
  }

  function assign(
    uint256 optionID
  ) external {
  }

  function recover(
  ) external {
  }

  function _getOption(uint256 optionID) private returns (NFTOption storage) {
    return options[optionID];
  }

  function _nftOwner(address nft) private returns (address) {
    // not completed yet

    returns address(0);
  }

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
}
