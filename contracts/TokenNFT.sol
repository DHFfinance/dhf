// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract TokenNFT is ERC721Enumerable, Ownable {
    uint256 public constant OFFSET = 1000000;

    // Optional mapping for token URIs
    mapping(uint256 => string) internal _typeURIs;
    mapping(uint256 => uint256) public typeTotalSupply;

    address public keeper;
    mapping(address => bool) public checkAddress;
    bool public isLimit;

    modifier onlyKeeper() {
        require(keeper == msg.sender, "Keeper only");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        _transferOwnership(msg.sender);
    }

    function tokenURI(uint256 tokenId_) public view virtual override returns (string memory) {
        _requireMinted(tokenId_);

        string memory _typeURI = _typeURIs[tokenId_/OFFSET];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _typeURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_typeURI).length > 0) {
            return string(abi.encodePacked(base, _typeURI));
        }

        return super.tokenURI(tokenId_);
    }

    function mint(address to_, uint256 typeId_) external onlyKeeper returns (uint256 tokenId_) {
        tokenId_ = OFFSET * typeId_ + typeTotalSupply[typeId_];
        typeTotalSupply[typeId_] += 1;

        _safeMint(to_, tokenId_);
    }

    function batchMint(address to_, uint256 typeId_, uint256 amount_) external onlyKeeper returns (uint256[] memory tokenIds_) {
        tokenIds_ = new uint256[](amount_);
        uint256 totalSupply_ = typeTotalSupply[typeId_];
        uint256 newTokenId_ = OFFSET * typeId_ + totalSupply_;
        typeTotalSupply[typeId_] = totalSupply_ + amount_;
        for(uint256 i=0;i<amount_;i++){
            uint256 tokenId_ = newTokenId_ + i;
            tokenIds_[i] = tokenId_;
            _safeMint(to_, tokenId_);
        }
    }

    function setTypeURI(uint256 typeId_, string calldata uri_) external onlyOwner {
        _typeURIs[typeId_] = uri_;
    }

    function setIsLimit() external onlyOwner {
        isLimit = !isLimit;
    }

    function setCheckAddress(address addr_, bool state_) external onlyOwner {
        checkAddress[addr_] = state_;
    }

    function transferKeeper(address account_) external onlyOwner {
        require(account_ != address(0), "Invalid zero address");
        keeper = account_;
    }

    function _transfer(
        address from_,
        address to_,
        uint256 tokenId_
    ) internal override {
        require(!isLimit || (checkAddress[to_]||checkAddress[from_]), "Limit") ;
        super._transfer(from_, to_, tokenId_);
    }

}
