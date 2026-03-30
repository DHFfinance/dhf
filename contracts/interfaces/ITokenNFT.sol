// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface ITokenNFT  is IERC721Enumerable {
    function typeTotalSupply(uint256 typeId_) external view returns(uint256);

    function mint(address to_, uint256 typeId_) external returns (uint256 tokenId_);
}