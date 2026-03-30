// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Community is OwnableUpgradeable {

    address public constant ROOT = address(0x01);

    // uid=>user=>referrer
    mapping(uint256 => mapping(address => address)) public referrer;

    event EventAddReferrer(uint256 indexed uid, address indexed user, address referrer);
    event EventReplaceReferrer(uint256 indexed uid, address indexed user, address newReferrer, address oldReferrer);

    modifier onlyAdmin() {
        require(owner() == msg.sender, "Caller is not the Admin");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function referrerOf(uint256 uid_, address account_) external view returns (address) {
        return referrer[uid_][account_];
    }

    function getReferrers(uint256 uid_, address[] calldata accountList_) external view returns (address[] memory referrerList_) {
        uint256 len_ = accountList_.length;
        referrerList_ = new address[](len_);
        for(uint256 i=0;i<len_;i++) {
            referrerList_[i] = referrer[uid_][accountList_[i]];
        }
    }

    function isSameLine(uint256 uid_, address user_, address child_) external view returns(bool) {
        for(uint256 i=0;i<100;i++) {
            address referrer_ = referrer[uid_][child_];
            if (user_ == referrer_) {
                return true;
            }
            child_ = referrer_;
            if (child_ == ROOT) {
                break;
            }
        }
        return false;
    }

    function addReferrer(uint256 uid_, address referrer_) external {
        require(referrer_ != msg.sender, "Referrer is yourself");
        require(referrer[uid_][msg.sender] == address(0), "Referrer exists");
        require(referrer[uid_][referrer_] != address(0) || referrer_ == ROOT, "Referrer not invited");

        referrer[uid_][msg.sender] = referrer_;

        emit EventAddReferrer(uid_, msg.sender, referrer_);
    }

    function updateReferrer(uint256 uid_, address[2][] calldata referrers_) external onlyAdmin {
        uint256 len_ = referrers_.length;
        for(uint256 i=0;i<len_;i++) {
            address user_ = referrers_[i][0];
            address referrer_ = referrers_[i][1];
            require(referrer_ != user_, "Referrer is yourself");
            require(referrer[uid_][user_] == address(0), "Referrer exists");

            referrer[uid_][user_] = referrer_;
            emit EventAddReferrer(uid_, user_, referrer_);
        }
    }

    /// replaceReferrers_ = [[user, new referrer, old referrer], ]
    function forceReplaceReferrer(uint256 uid_, address[3][] calldata replaceReferrers_) external onlyOwner {
        uint256 len_ = replaceReferrers_.length;
        for(uint256 i=0;i<len_;i++) {
            address user_ = replaceReferrers_[i][0];
            address referrer_ = replaceReferrers_[i][1];
            address oldReferrer_ = replaceReferrers_[i][2];
            require(referrer_ != user_, "Referrer is yourself");
            require(referrer_ != oldReferrer_, "Referrer is no change");
            require(referrer[uid_][user_] == oldReferrer_, "Old referrer error");

            referrer[uid_][user_] = referrer_;
            emit EventReplaceReferrer(uid_, user_, referrer_, oldReferrer_);
        }
    }

}
