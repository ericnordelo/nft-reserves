// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./governance/ProtocolParameters.sol";
import "./ReserveMarketplace.sol";

/**
 * @title contract managing the active reserves
 */
contract ReservesManager is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice the address of the reserves marketplace
    ReserveMarketplace public immutable marketplace;

    /// @notice the address of the protocol parameters contract controlled by governance
    ProtocolParameters public immutable protocol;

    /**
     * @dev the initializer modifier is to avoid someone initializing
     *      the implementation contract after deployment
     */
    constructor(address marketplace_, address protocolParameters_) initializer {
        marketplace = ReserveMarketplace(marketplace_);
        protocol = ProtocolParameters(protocolParameters_);
    }

    /**
     * @dev initializes the contract
     */
    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
