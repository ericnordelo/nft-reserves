// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title parameters controlled by governance
 * @notice the owner of this contract should be the
 *         timelock controller of the governance feature
 */
contract ProtocolParameters is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice minimum duration in seconds of a reserve
    uint256 public minimumReservePeriod;

    event MinimumReservePeriodUpdated(uint256 from, uint256 to);

    /**
     * @dev the initializer modifier is to avoid someone initializing
     *      the implementation contract after deployment
     */
    constructor() initializer {}

    /**
     * @dev initializes the contract,
     *      sets the default (initial) values of the parameters
     *      and also transfers the ownership to the governance
     */
    function initialize(uint256 minimumReservePeriod_, address governanceContractAddress_)
        public
        initializer
    {
        require(minimumReservePeriod_ > 0, "Invalid minimum reserve period");
        minimumReservePeriod = minimumReservePeriod_;

        __Ownable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        transferOwnership(governanceContractAddress_);
    }

    function setMinimumReservePeriod(uint256 minimumReservePeriod_) external onlyOwner {
        require(minimumReservePeriod_ > 0, "Invalid minimum reserve period");
        emit MinimumReservePeriodUpdated(minimumReservePeriod, minimumReservePeriod_);
        minimumReservePeriod = minimumReservePeriod_;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
