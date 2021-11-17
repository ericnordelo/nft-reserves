// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title parameters controlled by governance
 * @notice the owner of this contract should be the
 *         timelock controller of the governance feature
 */
contract ProtocolParameters is Ownable {
    /// @notice minimum duration in seconds of a reserve
    uint256 public minimumReservePeriod;

    event MinimumReservePeriodUpdated(uint256 from, uint256 to);

    /**
     * @dev sets the default (initial) values of the parameters
     *      also transfers the ownership to the governance
     */
    constructor(uint256 minimumReservePeriod_, address governanceContractAddress_) {
        require(minimumReservePeriod_ > 0, "Invalid minimum reserve period");

        minimumReservePeriod = minimumReservePeriod_;

        // transfer ownership
        transferOwnership(governanceContractAddress_);
    }

    function setMinimumReservePeriod(uint256 minimumReservePeriod_) external onlyOwner {
        require(minimumReservePeriod_ > 15 minutes, "Flipping Interval should be greater than 15 minutes");
        emit MinimumReservePeriodUpdated(minimumReservePeriod, minimumReservePeriod_);
        minimumReservePeriod = minimumReservePeriod_;
    }
}
