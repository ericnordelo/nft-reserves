// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

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
  
  struct NFTOption {
    address owner;
    address nft;
    uint256 expiry;
    uint256 pct;
    uint256 optionID;
  }

  uint256 counter;

  mapping(uint256 => NFTOption) options;

  constructor() public {
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

  function _getOption(uint256 optionID) private returns (NFTOption storage) {
    return options[optionID];
  }

  function _nftOwner(address nft) private returns (address) {
    // not completed yet

    returns address(0);
  }
}
