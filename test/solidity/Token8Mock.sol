// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token8Mock is ERC20 {
    constructor() ERC20("Test Token8", "Token8") {
        _mint(msg.sender, 10000000 * 10**decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
