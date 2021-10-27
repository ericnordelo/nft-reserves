// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract PriviNFTBuying {
  event OptionCreated(
    address owner,
    address nft,
    uint256 expiry,
    uint256 price,
    uint256 pct,
    uint256 id
  );

  event OptionCanceled(
    address owner,
    uint256 id
  );

  event OptionSold(
    address owner,
    address buyer,
    uint256 id
  );
  
  struct NFTOption {
    address owner;
    address nft;
    uint256 expiry;
    uint256 pct;
    uint256 id;
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
  ) external returns (uint256 id) {
    id = counter;
    counter++;
    emit OptionCreated(msg.sender, nft, expiry, price, pct, id);
  }
  
  function cancelOption(
    uint256 id
  ) external returns (bool success) {

  }

  function buyOption(
    uint256 id
  ) external returns (bool success) {

  }
}
