// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract EmptyContract is AccessControlUpgradeable {
    error ErrorCallerNotManager();

    modifier onlyManager() {
        _onlyManager();
        _;
    }

    function _onlyManager() internal view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert ErrorCallerNotManager();
    }

    function initialize() public virtual initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
