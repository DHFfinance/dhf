// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

interface IStakePool {
    function addStakeLPPower(uint256 amount_, address user_) external;
    function notifyRewards(uint256 amount_) external;
}