// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IERC20Token is IERC20Upgradeable, IERC20MetadataUpgradeable {
    function mint(address to, uint256 number) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function sync() external;
}
