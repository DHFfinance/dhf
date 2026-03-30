// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface IBonusPool {
    function mining(uint256 amount_) external;
    function allotBonus(uint256 amount_) external payable;
    function allotBonusFromLP(uint256 amount_) external;
    function sendLPReward(address user_, uint256 amount_) external;
    function sendNFTReward(address user_, uint256 amount_) external;
    function sendSwapFeeReward(address user_, uint256 amount_) external;
    function sendSellReward(address user_, uint256 amount_) external;
}