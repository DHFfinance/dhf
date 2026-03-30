// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20TokenX is IERC20Metadata {
    function burn(uint256 amount) external;

    function burnFrom(address account_, uint256 amount_) external;

    function grantRole(bytes32 role_, address account_) external;

    function revokeRole(bytes32 role_, address account_) external;

    function burnFromJLP(uint256 amount_) external;

    function updateUser(address user_) external;

    function getBonusInfo(
        address recipient_
    )
        external
        view
        returns (uint256 index_, uint256 supplyIndex_, uint256 claimables_);

}
