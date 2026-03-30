// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ICommunity} from "./interfaces/ICommunity.sol";
import {IStakePool} from "./interfaces/IStakePool.sol";
import {IERC20Token} from "./interfaces/IERC20Token.sol";
import {ITokenNFT} from "./interfaces/ITokenNFT.sol";
import {IBonusPool} from "./interfaces/IBonusPool.sol";
import {EmptyContract} from "./EmptyContract.sol";
import {IRouter} from "./interfaces/jswap/IRouter.sol";
import {IPool} from "./interfaces/jswap/IPool.sol";

contract NFTPresell is ERC721Holder, EmptyContract {
    using SafeERC20Upgradeable for IERC20Token;

    uint256 public constant UID = 1;

    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant _PRECISION = 10 ** 18;
    uint256 internal constant _SMALLTYPE = 2;
    uint256 internal constant _DAOTYPE = 3;
    uint256 internal constant _SMALLNODEID = 201;
    uint256 internal constant _DAONODEID = 301;

    address public immutable USDT;
    address public immutable DNFT;
    address public immutable XTOKEN;
    address public immutable JLP_USDT_X;
    address public immutable SWAPROUTER; // JSWAP
    address public immutable SWAPFACTORY;
    ICommunity public immutable COMMUNITY;
    address public immutable BONUSPOOL;
    address public immutable STAKEPOOL;

    // user=>nType=>data
    mapping(address => mapping(uint256 => PurchaseData)) public purchaseList;
    struct PurchaseData {
        address payToken;
        uint256 amount;
        uint256 payTime;
        uint256 nodeId;
        uint256 nftId;
    }

    mapping(uint256 => NodeConfig) public nodeConfigs;
    struct NodeConfig {
        address payToken;
        uint256 payAmount;
        uint256 nType;
        uint256 maxLimit;
    }
    mapping(uint256 => uint256) public nodeCurNums;

    mapping(address => uint256) public nftsPower;
    uint256 public totalNFTsPower;

    mapping(uint256 => mapping(address => bool)) public whiteList;

    RewardData public nftRewardData;
    RewardData public swapFeeDaoRewardData;
    RewardData public swapFeeSmallRewardData;
    RewardData public daoSellRewardData;
    RewardData public smallSellRewardData;

    struct RewardData {
        uint256 totalReward;
        uint256 totalClaimed;
        uint256 rewardPerStored;
        mapping(address => uint256) userRewards;
        mapping(address => uint256) claimed;
        mapping(address => uint256) userRewardPerStored;
    }

    // ======= function params struct =======
    struct NodeConfigParam {
        uint256 nodeId;
        address payToken;
        uint256 payAmount;
        uint256 nType;
        uint256 maxLimit;
        uint256 curNum;
    }

    error ErrorAddressZero();
    error ErrorCaller();
    error ErrorReferrer();
    error ErrorEmptyReward();
    error ErrorPurchased();
    error ErrorLimit();
    error ErrorNodeError();
    error ErrorWhiteList();

    modifier onlyBonusPool() {
        if(msg.sender != BONUSPOOL) revert ErrorCaller();
        _;
    }

    modifier updateRewards(address user_) {
        if (user_ != address(0)) {
            _updateNFTRewards(user_);
            _updateSwapFeeSmallRewards(user_);
            _updateSwapFeeDaoRewards(user_);
            _updateSellSmallRewards(user_);
            _updateSellDaoRewards(user_);
        }
        _;
    }

    /* ======== INITIALIZATION ======== */
    constructor(
        address USDT_,
        address DNFT_,
        address XTOKEN_,
        address JLP_USDT_X_,
        address SWAPROUTER_,
        address SWAPFACTORY_,
        address COMMUNITY_,
        address STAKEPOOL_,
        address BONUSPOOL_
    ) {
        if (USDT_ == address(0)
            || DNFT_ == address(0)
            || XTOKEN_ == address(0)
            || JLP_USDT_X_ == address(0)
            || SWAPROUTER_ == address(0)
            || SWAPFACTORY_ == address(0)
            || COMMUNITY_ == address(0)
            || STAKEPOOL_ == address(0)
            || BONUSPOOL_ == address(0)
        ) revert ErrorAddressZero();

        USDT = USDT_;
        DNFT = DNFT_;
        XTOKEN = XTOKEN_;
        JLP_USDT_X = JLP_USDT_X_;
        SWAPROUTER = SWAPROUTER_;
        SWAPFACTORY = SWAPFACTORY_;
        COMMUNITY = ICommunity(COMMUNITY_);
        STAKEPOOL = STAKEPOOL_;
        BONUSPOOL = BONUSPOOL_;
    }

    function reinitialize() public onlyManager reinitializer(2) {
        IERC20Token( USDT ).approve( SWAPROUTER, type(uint256).max );
        IERC20Token( XTOKEN ).approve( SWAPROUTER, type(uint256).max );
    }

    function getBatchPurchaseData(address[] calldata users_, uint256 nType_)
        external view
        returns (PurchaseData[] memory dataList_)
    {
        uint256 len_ = users_.length;
        dataList_ = new PurchaseData[](len_);
        for(uint256 i=0;i<len_;i++) {
            dataList_[i] = purchaseList[users_[i]][nType_];
        }
    }

    function getPurchaseList(address[] calldata users_, uint256 nType_)
        external view
        returns (
            uint256[] memory amountList_,
            uint256[] memory nodeIds_
    ) {
        uint256 len_ = users_.length;
        amountList_ = new uint256[](len_);
        nodeIds_ = new uint256[](len_);
        for(uint256 i=0;i<len_;i++) {
            PurchaseData memory data_ = purchaseList[users_[i]][nType_];
            amountList_[i] = data_.amount;
            nodeIds_[i] = data_.nodeId;
        }
    }

    function getUserPurchase(address user_, uint256[] calldata nTypeList_)
    external view
    returns (PurchaseData[] memory dataList_)
    {
        uint256 len_ = nTypeList_.length;
        dataList_ = new PurchaseData[](len_);
        for(uint256 i=0;i<len_;i++) {
            dataList_[i] = purchaseList[user_][nTypeList_[i]];
        }
    }

    function getNodeConfigs(uint256[] calldata nodeIds_) external view returns(NodeConfigParam[] memory nodeConfigs_){
        uint256 len_ = nodeIds_.length;
        nodeConfigs_ = new NodeConfigParam[](len_);
        for(uint256 i=0;i<len_;i++) {
            NodeConfig memory config_ = nodeConfigs[nodeIds_[i]];
            nodeConfigs_[i] = NodeConfigParam(
                nodeIds_[i],
                config_.payToken,
                config_.payAmount,
                config_.nType,
                config_.maxLimit,
                nodeCurNums[nodeIds_[i]]
            );
        }
    }

    function nftPresell(uint256 nodeId_) external updateRewards(msg.sender) {
        _checkUser(msg.sender);
        if (!whiteList[nodeId_][msg.sender]) revert ErrorWhiteList();
        NodeConfig memory config_ = nodeConfigs[nodeId_];
        if (purchaseList[msg.sender][config_.nType].amount > 0) revert ErrorPurchased();
        uint256 curNum_ = nodeCurNums[nodeId_];
        if(curNum_ >= config_.maxLimit) revert ErrorLimit();
        if(config_.payToken == address(0)) revert ErrorNodeError();

        PurchaseData storage data_ = purchaseList[msg.sender][config_.nType];

        data_.payToken = config_.payToken;
        data_.amount = config_.payAmount;
        data_.payTime = block.timestamp;
        data_.nodeId = nodeId_;

        curNum_ += 1;
        nodeCurNums[nodeId_] = curNum_;
        _addNFTPower(msg.sender, config_.payAmount);
        IStakePool(STAKEPOOL).addStakeLPPower(config_.payAmount, msg.sender);

        IERC20Token(config_.payToken).safeTransferFrom(msg.sender, address(this), config_.payAmount);
        uint256 liqudity_ = _addLiquidity(config_.payAmount);

        uint256 nftId_ = ITokenNFT(DNFT).mint(msg.sender, config_.nType);
        data_.nftId = nftId_;

        emit EventNFTPresell(
            msg.sender,
            config_.payToken,
            config_.payAmount,
            liqudity_,
            block.timestamp,
            curNum_,
            nodeId_,
            config_.nType,
            nftId_,
            nftsPower[msg.sender]
        );
    }

    function claimNFTReward() external updateRewards(msg.sender) {
        address user_ = msg.sender;
        _checkUser(user_);

        uint256 reward_ = nftRewardData.userRewards[user_];
        if (reward_ == 0) revert ErrorEmptyReward();

        nftRewardData.userRewards[user_] = 0;
        nftRewardData.claimed[user_] += reward_;
        uint256 totalClaimed_ = nftRewardData.totalClaimed + reward_;
        nftRewardData.totalClaimed = totalClaimed_;
        IBonusPool(BONUSPOOL).sendNFTReward(user_, reward_);

        emit EventClaimNFTReward(user_, reward_, totalClaimed_);
    }

    function claimNodeReward() external updateRewards(msg.sender) {
        address user_ = msg.sender;
        _checkUser(user_);

        // swap fee
        uint256 rewardSmall_ = _claimSwapFeeSmallReward(user_);
        uint256 rewardDAO_ = _claimSwapFeeDaoReward(user_);
        uint256 reward_ = rewardSmall_ + rewardDAO_;
        if (reward_ > 0) {
            IBonusPool(BONUSPOOL).sendSwapFeeReward(user_, reward_);
            emit EventClaimSwapFeeReward(user_, reward_, rewardSmall_, rewardDAO_);
        }

        // sell
        uint256 sellSmall_ = _claimSellSmallReward(user_);
        uint256 sellDAO_ = _claimSellDaoReward(user_);
        uint256 rewardSell_ = sellSmall_ + sellDAO_;
        if (rewardSell_ > 0) {
            IBonusPool(BONUSPOOL).sendSellReward(user_, rewardSell_);
            emit EventClaimSellReward(user_, rewardSell_, sellSmall_, sellDAO_);
        } else if (reward_ == 0) {
            revert ErrorEmptyReward();
        }
    }

    function _claimSwapFeeSmallReward(address user_) internal returns(uint256 reward_) {
        reward_ = swapFeeSmallRewardData.userRewards[user_];
        if (reward_ == 0) return 0;

        swapFeeSmallRewardData.userRewards[user_] = 0;
        swapFeeSmallRewardData.claimed[user_] += reward_;
        swapFeeSmallRewardData.totalClaimed += reward_;
    }

    function _claimSwapFeeDaoReward(address user_) internal returns(uint256 reward_) {
        reward_ = swapFeeDaoRewardData.userRewards[user_];
        if (reward_ == 0) return 0;

        swapFeeDaoRewardData.userRewards[user_] = 0;
        swapFeeDaoRewardData.claimed[user_] += reward_;
        swapFeeDaoRewardData.totalClaimed += reward_;
    }

    function _claimSellSmallReward(address user_) internal returns(uint256 reward_) {
        reward_ = smallSellRewardData.userRewards[user_];
        if (reward_ == 0) return 0;

        smallSellRewardData.userRewards[user_] = 0;
        smallSellRewardData.claimed[user_] += reward_;
        smallSellRewardData.totalClaimed += reward_;
    }

    function _claimSellDaoReward(address user_) internal returns(uint256 reward_) {
        reward_ = daoSellRewardData.userRewards[user_];
        if (reward_ == 0) return 0;

        daoSellRewardData.userRewards[user_] = 0;
        daoSellRewardData.claimed[user_] += reward_;
        daoSellRewardData.totalClaimed += reward_;
    }

    function notifyNFTRewards(uint256 amount_) external onlyBonusPool {
        uint256 rewardPerStoredNew_ = nftRewardData.rewardPerStored;
        uint256 totalNFTsPower_ = totalNFTsPower;
        if (totalNFTsPower_ > 0) {
            rewardPerStoredNew_ += amount_ * _PRECISION / totalNFTsPower_;
            nftRewardData.rewardPerStored = rewardPerStoredNew_;
        }
        nftRewardData.totalReward += amount_;

        emit EventNotifyNFTReward(amount_, rewardPerStoredNew_, totalNFTsPower_);
    }

    function notifySwapFeeRewards(uint256 smallAmount_, uint256 daoAmount_) external onlyBonusPool {
        if (smallAmount_ > 0) {
            uint256 rewardPerStoredNew_ = swapFeeSmallRewardData.rewardPerStored;
            uint256 nodeNum_ = nodeCurNums[_SMALLNODEID];
            if (nodeNum_ > 0) {
                rewardPerStoredNew_ += smallAmount_ / nodeNum_;
                swapFeeSmallRewardData.rewardPerStored = rewardPerStoredNew_;
            }
            swapFeeSmallRewardData.totalReward += smallAmount_;

            emit EventNotifySwapFeeSmallReward(smallAmount_, rewardPerStoredNew_, nodeNum_);
        }
        if (daoAmount_ > 0) {
            uint256 rewardPerStoredNew_ = swapFeeDaoRewardData.rewardPerStored;
            uint256 nodeNum_ = nodeCurNums[_DAONODEID];
            if (nodeNum_ > 0) {
                rewardPerStoredNew_ += daoAmount_ / nodeNum_;
                swapFeeDaoRewardData.rewardPerStored = rewardPerStoredNew_;
            }
            swapFeeDaoRewardData.totalReward += daoAmount_;

            emit EventNotifySwapFeeDaoReward(daoAmount_, rewardPerStoredNew_, nodeNum_);
        }
    }

    function notifyTokenXSellRewards(uint256 smallAmount_, uint256 daoAmount_) external onlyBonusPool {
        if (smallAmount_ > 0) {
            uint256 rewardPerStoredNew_ = smallSellRewardData.rewardPerStored;
            uint256 nodeNum_ = nodeCurNums[_SMALLNODEID];
            if (nodeNum_ > 0) {
                rewardPerStoredNew_ += smallAmount_ / nodeNum_;
                smallSellRewardData.rewardPerStored = rewardPerStoredNew_;
            }
            smallSellRewardData.totalReward += smallAmount_;

            emit EventNotifySmallSellReward(smallAmount_, rewardPerStoredNew_, nodeNum_);
        }
        if (daoAmount_ > 0) {
            uint256 rewardPerStoredNew_ = daoSellRewardData.rewardPerStored;
            uint256 nodeNum_ = nodeCurNums[_DAONODEID];
            if (nodeNum_ > 0) {
                rewardPerStoredNew_ += daoAmount_ / nodeNum_;
                daoSellRewardData.rewardPerStored = rewardPerStoredNew_;
            }
            daoSellRewardData.totalReward += daoAmount_;

            emit EventNotifyDaoSellReward(daoAmount_, rewardPerStoredNew_, nodeNum_);
        }
    }

    function getRewardData(address user_) public view returns(uint256, uint256, uint256, uint256, uint256) {
        return (
            nftRewardData.userRewards[user_] + powerEarnedNew(user_),
            swapFeeSmallRewardData.userRewards[user_] + swapFeeSmallEarnedNew(user_),
            swapFeeDaoRewardData.userRewards[user_] + swapFeeDaoEarnedNew(user_),
            smallSellRewardData.userRewards[user_] + smallSellEarnedNew(user_),
            daoSellRewardData.userRewards[user_] + daoSellEarnedNew(user_)
        );
}

    function powerEarnedNew(address user_) public view returns (uint256) {
        return (nftsPower[user_] * (nftRewardData.rewardPerStored - nftRewardData.userRewardPerStored[user_])) / _PRECISION;
    }

    function swapFeeSmallEarnedNew(address user_) public view returns (uint256) {
        if (purchaseList[user_][_SMALLTYPE].amount == 0) {
            return 0;
        }
        return swapFeeSmallRewardData.rewardPerStored - swapFeeSmallRewardData.userRewardPerStored[user_];
    }

    function swapFeeDaoEarnedNew(address user_) public view returns (uint256) {
        if (purchaseList[user_][_DAOTYPE].amount == 0) {
            return 0;
        }
        return swapFeeDaoRewardData.rewardPerStored - swapFeeDaoRewardData.userRewardPerStored[user_];
    }

    function smallSellEarnedNew(address user_) public view returns (uint256) {
        if (purchaseList[user_][_SMALLTYPE].amount == 0) {
            return 0;
        }
        return smallSellRewardData.rewardPerStored - smallSellRewardData.userRewardPerStored[user_];
    }

    function daoSellEarnedNew(address user_) public view returns (uint256) {
        if (purchaseList[user_][_DAOTYPE].amount == 0) {
            return 0;
        }
        return daoSellRewardData.rewardPerStored - daoSellRewardData.userRewardPerStored[user_];
    }

    function setNodeConfigs(NodeConfigParam[] calldata nodeConfigs_) external onlyManager {
        uint256 len_ = nodeConfigs_.length;
        for(uint256 i=0;i<len_;i++) {
            nodeConfigs[nodeConfigs_[i].nodeId] = NodeConfig(
                nodeConfigs_[i].payToken,
                nodeConfigs_[i].payAmount,
                nodeConfigs_[i].nType,
                nodeConfigs_[i].maxLimit
            );
        }
    }

    function deleteNodeConfig(uint256[] calldata nodeIds_) external onlyManager {
        uint256 len_ = nodeIds_.length;
        for(uint256 i=0;i<len_;i++) {
            delete nodeConfigs[nodeIds_[i]];
        }
    }

    function setWhiteList(address[] calldata users_, uint256 nodeId_, bool state_) external onlyManager {
        uint256 len_ = users_.length;
        for(uint256 i=0;i<len_;i++) {
            whiteList[nodeId_][users_[i]] = state_;
        }
    }

    function _checkUser(address user_) internal view {
        if (COMMUNITY.referrerOf(UID, user_) == address(0)) revert ErrorReferrer();
    }

    function _updateNFTRewards(address user_) internal {
        if (nftRewardData.userRewardPerStored[user_] == nftRewardData.rewardPerStored) return;
        uint256 rewardNew_ = powerEarnedNew(user_);
        if (rewardNew_ > 0) {
            nftRewardData.userRewards[user_] += rewardNew_;
        }
        nftRewardData.userRewardPerStored[user_] = nftRewardData.rewardPerStored;
    }

    function _updateSwapFeeSmallRewards(address user_) internal {
        if (swapFeeSmallRewardData.userRewardPerStored[user_] == swapFeeSmallRewardData.rewardPerStored) return;
        uint256 rewardNew_ = swapFeeSmallEarnedNew(user_);
        if (rewardNew_ > 0) {
            swapFeeSmallRewardData.userRewards[user_] += rewardNew_;
        }
        swapFeeSmallRewardData.userRewardPerStored[user_] = swapFeeSmallRewardData.rewardPerStored;
    }

    function _updateSwapFeeDaoRewards(address user_) internal {
        if (swapFeeDaoRewardData.userRewardPerStored[user_] == swapFeeDaoRewardData.rewardPerStored) return;
        uint256 rewardNew_ = swapFeeDaoEarnedNew(user_);
        if (rewardNew_ > 0) {
            swapFeeDaoRewardData.userRewards[user_] += rewardNew_;
        }
        swapFeeDaoRewardData.userRewardPerStored[user_] = swapFeeDaoRewardData.rewardPerStored;
    }

    function _updateSellSmallRewards(address user_) internal {
        if (smallSellRewardData.userRewardPerStored[user_] == smallSellRewardData.rewardPerStored) return;
        uint256 rewardNew_ = smallSellEarnedNew(user_);
        if (rewardNew_ > 0) {
            smallSellRewardData.userRewards[user_] += rewardNew_;
        }
        smallSellRewardData.userRewardPerStored[user_] = smallSellRewardData.rewardPerStored;
    }

    function _updateSellDaoRewards(address user_) internal {
        if (daoSellRewardData.userRewardPerStored[user_] == daoSellRewardData.rewardPerStored) return;
        uint256 rewardNew_ = daoSellEarnedNew(user_);
        if (rewardNew_ > 0) {
            daoSellRewardData.userRewards[user_] += rewardNew_;
        }
        daoSellRewardData.userRewardPerStored[user_] = daoSellRewardData.rewardPerStored;
    }

    function _addNFTPower(address user_, uint256 power_) internal {
        totalNFTsPower += power_;
        nftsPower[user_] += power_;
    }

    function _getRouteFromToken(address fromToken_, address toToken_, bool isStable_) internal view returns (IRouter.Route memory) {
        return IRouter.Route({
            from: fromToken_,
            to: toToken_,
            stable: isStable_,
            factory: SWAPFACTORY
        });
    }

    function _getTokenPrice(address lp_, address tokenIn_, uint256 amount_) internal view returns (uint256) {
        address token0 = IPool(lp_).token0();
        (uint256 reserveA, uint256 reserveB, ) = IPool(lp_).getReserves();
        return tokenIn_ == token0 ? amount_ * reserveB / reserveA : amount_ * reserveA / reserveB;
    }

    function _swapUSDTToX(uint256 amount_, address recipient_) internal returns (uint256){
        IRouter.Route[] memory route_ = new IRouter.Route[](1);
        route_[0] = _getRouteFromToken(USDT, XTOKEN, false);
        uint256[] memory amounts_ = IRouter(SWAPROUTER).swapExactTokensForTokens(amount_, 0, route_, recipient_, block.timestamp);
        return amounts_[amounts_.length - 1];
    }

    function _addLiquidity(uint256 tokenAmount_) internal returns(uint256) {
        uint256 swappedXAmount_ = _swapUSDTToX(tokenAmount_/2, address(this));
        (, uint256 costX_, uint256 liquidity_) = IRouter(SWAPROUTER).addLiquidity(
            USDT,
            XTOKEN,
            false,
            tokenAmount_/2,
            swappedXAmount_,
            0,
            0,
            BLACK_HOLE,
            block.timestamp
        );
        if (costX_ < swappedXAmount_) {
            IERC20Token(XTOKEN).safeTransfer(JLP_USDT_X, swappedXAmount_ - costX_);
            IPool(JLP_USDT_X).sync();
        }
        emit EventAddLiquidity(tokenAmount_, swappedXAmount_, liquidity_);
        return liquidity_;
    }

    event EventNFTPresell(
        address indexed user,
        address payToken,
        uint256 amount,
        uint256 liquidity,
        uint256 time,
        uint256 num,
        uint256 nodeId,
        uint256 nType,
        uint256 nftId,
        uint256 userNFTPower
    );
    event EventClaimNFTReward(
        address indexed user,
        uint256 reward,
        uint256 totalNFTClaimed
    );
    event EventClaimSwapFeeReward(
        address indexed user,
        uint256 reward,
        uint256 rewardSmall,
        uint256 rewardDAO
    );
    event EventClaimSellReward(
        address indexed user,
        uint256 reward,
        uint256 rewardSmall,
        uint256 rewardDAO
    );
    event EventNotifyNFTReward(
        uint256 amount,
        uint256 rewardPerStoredNew,
        uint256 totalNFTsPower
    );
    event EventNotifySwapFeeSmallReward(
        uint256 amount,
        uint256 rewardPerStoredNew,
        uint256 nodeNum
    );
    event EventNotifySwapFeeDaoReward(
        uint256 amount,
        uint256 rewardPerStoredNew,
        uint256 nodeNum
    );
    event EventNotifySmallSellReward(
        uint256 amount,
        uint256 rewardPerStoredNew,
        uint256 nodeNum
    );
    event EventNotifyDaoSellReward(
        uint256 amount,
        uint256 rewardPerStoredNew,
        uint256 nodeNum
    );
    event EventAddLiquidity(uint256 tokenAmount, uint256 swappedXAmount, uint256 liquidity);
}
