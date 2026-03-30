// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface INFTPresell {
    function notifyNFTRewards(uint256 amount_) external;
    function notifySwapFeeRewards(uint256 smallAmount_, uint256 daoAmount_) external;
    function notifyTokenXSellRewards(uint256 smallAmount_, uint256 daoAmount_) external;
}