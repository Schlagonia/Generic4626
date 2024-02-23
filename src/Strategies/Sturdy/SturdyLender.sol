// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Base4626} from "../../Base4626.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

contract SturdyLender is Base4626, AuctionSwapper {
    constructor(
        address _asset,
        string memory _name,
        address _vault
    ) Base4626(_asset, _name, _vault) {}

    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            require(Auction(_auction).want() == address(asset), "wrong want");
        }
        auction = _auction;
    }

    function _auctionKicked(
        address _token
    ) internal virtual override returns (uint256) {
        require(_token != address(asset), "asset");
        return super._auctionKicked(_token);
    }
}
