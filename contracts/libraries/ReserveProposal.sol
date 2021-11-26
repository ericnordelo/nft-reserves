// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Structs.sol";
import "./Constants.sol";

library ReserveProposal {
    /**
     * @dev helper for trying to automatically sell a reserve sale proposal
     *      tranferring the collateral and the NFT
     */
    function tryToSellReserve(PurchaseReserveProposal memory purchaseProposal_, address fundsManager_)
        internal
        returns (bool sold)
    {
        // check if proposal is expired
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > purchaseProposal_.expirationTimestamp) {
            return false;
        }

        // try to make the transfer from the buyer (the collateral)
        try
            IERC20(purchaseProposal_.paymentToken).transferFrom(
                purchaseProposal_.buyer,
                fundsManager_,
                (purchaseProposal_.collateralPercent * purchaseProposal_.price) /
                    (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS)
            )
        returns (bool success) {
            if (!success) {
                return false;
            }
        } catch {
            return false;
        }

        // if the previous transfer was successfull transfer the NFT
        IERC721(purchaseProposal_.collection).transferFrom(
            msg.sender,
            fundsManager_,
            purchaseProposal_.tokenId
        );

        sold = true;
    }

    /**
     * @dev helper for trying to automatically buy from a purchase proposal
     */
    function tryToBuyReserve(SaleReserveProposal memory saleProposal_, address fundsManager_)
        internal
        returns (bool bought)
    {
        // check if proposal is expired
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > saleProposal_.expirationTimestamp) {
            return false;
        }

        // try to make the transfer from the seller
        try
            IERC721(saleProposal_.collection).transferFrom(
                saleProposal_.owner,
                fundsManager_,
                saleProposal_.tokenId
            )
        {
            // if the previous transfer was successfull transfer the NFT
            require(
                IERC20(saleProposal_.paymentToken).transferFrom(
                    msg.sender,
                    fundsManager_,
                    (saleProposal_.collateralPercent * saleProposal_.price) /
                        (100 * 10**Constants.COLLATERAL_PERCENT_DECIMALS)
                ),
                "Fail to transfer"
            );
        } catch {
            return false;
        }

        bought = true;
    }
}
