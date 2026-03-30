// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IRouter} from "./interfaces/jswap/IRouter.sol";
import {IPool} from "./interfaces/jswap/IPool.sol";
import {IERC20Token} from "./interfaces/IERC20Token.sol";
import {IERC20TokenX} from "./interfaces/IERC20TokenX.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ICommunity} from "./interfaces/ICommunity.sol";
import {IBonusPool} from "./interfaces/IBonusPool.sol";
import {EmptyContract} from "./EmptyContract.sol";

contract StakePool is EmptyContract {
    using SafeERC20Upgradeable for IERC20Token;

    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    bytes32 public constant ROOT_MANAGER = keccak256("ROOT_MANAGER");
    uint256 public constant POWER_GROWTH = 102;
    uint256 internal constant UID = 1;
    uint256 internal constant _PRECISION = 10 ** 18;

    ICommunity public immutable COMMUNITY;
    address public immutable SWAPROUTER; // JSWAP
    address public immutable SWAPFACTORY;
    address public immutable BONUSPOOL;
    address public immutable NFTPRESELL;

    address public immutable USDT;
    address public immutable XTOKEN;
    address public immutable JLP_USDT_X;

    uint256 public checkTime;
    uint256 public dayId;
    uint256 public dayPower;

    uint256 private _unlocked;

    mapping(address => uint256) public usersLpPower;
    uint256 public totalLpPower;

    mapping(address => uint256) public userClaimed;
    mapping(address => uint256) public userRewardPerStored;
    uint256 public rewardPerStored;
    mapping(address => uint256) public userRewards;
    uint256 public totalClaimed;
    uint256 public totalReward;

    error ErrorAccountError();
    error ErrorAddressZero();
    error ErrorCaller();
    error ErrorEmptyReward();
    error ErrorLocked();

    modifier lock() {
        if(_unlocked != 1) revert ErrorLocked();
        _toLock();
        _;
        _toUnlock();
    }

    modifier onlyRootManager() {
        _onlyRootManager();
        _;
    }

    modifier onlyBonusPool() {
        if(msg.sender != BONUSPOOL) revert ErrorCaller();
        _;
    }

    modifier onlyNFTPresell() {
        if(msg.sender != NFTPRESELL) revert ErrorCaller();
        _;
    }

    modifier checkDayId() {
        _checkDayId();
        _;
    }

    modifier updateRewards(address user_) {
        _updateRewards(user_);
        _;
    }

    constructor(
        address USDT_,
        address XTOKEN_,
        address JLP_USDT_X_,
        address COMMUNITY_,
        address SWAPROUTER_,
        address SWAPFACTORY_,
        address BONUSPOOL_,
        address NFTPRESELL_
    ) {
        if (USDT_ == address(0)
            || XTOKEN_ == address(0)
            || JLP_USDT_X_ == address(0)
            || COMMUNITY_ == address(0)
            || SWAPROUTER_ == address(0)
            || SWAPFACTORY_ == address(0)
            || BONUSPOOL_ == address(0)
            || NFTPRESELL_ == address(0)
        ) revert ErrorAddressZero();

        USDT = USDT_;
        XTOKEN = XTOKEN_;
        JLP_USDT_X = JLP_USDT_X_;
        COMMUNITY = ICommunity(COMMUNITY_);
        SWAPROUTER = SWAPROUTER_;
        SWAPFACTORY = SWAPFACTORY_;
        BONUSPOOL = BONUSPOOL_;
        NFTPRESELL = NFTPRESELL_;
    }

   function reinitialize(
       uint256 startTime_
   ) public onlyManager reinitializer(2) {
       require(startTime_ > block.timestamp, "Time error");

       checkTime = startTime_;

       dayId = 1;
       dayPower = 1e18;

       _unlocked = 1;
       IERC20Token( USDT ).approve( SWAPROUTER, type(uint256).max );
       IERC20Token( XTOKEN ).approve( SWAPROUTER, type(uint256).max );
   }

    function getUsersPower(address[] calldata usersList_) external view returns(uint256[] memory amountList_) {
        uint256 len_ = usersList_.length;
        amountList_ = new uint256[](len_);
        for(uint256 i=0;i<len_;i++) {
            amountList_[i] = usersLpPower[usersList_[i]];
        }
    }

    function earnedNew(address user_) public view returns (uint256) {
        return (usersLpPower[user_] * (rewardPerStored - userRewardPerStored[user_])) / _PRECISION;
    }

    function earned(address user_) public view returns (uint256) {
        return earnedNew(user_) + userRewards[user_];
    }

    function stake(address user_, uint256 amount_) external checkDayId lock updateRewards(msg.sender) {
        if(user_ != msg.sender) revert ErrorAccountError();
        _checkUser(user_);

        IERC20Token(USDT).safeTransferFrom(msg.sender, address(this), amount_);

        // swap 50% to X
        uint256 newXAmount_ = _swapUSDTToX(amount_ / 2, address(this));
        uint256 liquidity_ = _addLiquidity(amount_ / 2, newXAmount_);

        uint256 power_ = amount_ * dayPower / 10**18;
        usersLpPower[user_] += power_;
        totalLpPower += power_;

        emit EventStake(user_, amount_, power_, liquidity_, amount_ / 2, newXAmount_, block.timestamp);
    }

    function claimReward() external checkDayId lock updateRewards(msg.sender) {
        address user_ = msg.sender;
        _checkUser(user_);

        uint256 reward_ = userRewards[user_];
        if (reward_ == 0) revert ErrorEmptyReward();

        userRewards[user_] = 0;
        userClaimed[user_] += reward_;
        totalClaimed += reward_;
        IBonusPool(BONUSPOOL).sendLPReward(user_, reward_);

        emit EventClaimReward(user_, reward_, totalClaimed);
    }

    function sellToken(uint256 amount_) external checkDayId lock updateRewards(msg.sender) {
        address user_ = msg.sender;
        _checkUser(user_);

        IERC20Token(XTOKEN).safeTransferFrom(user_, address(this), amount_);

        uint256 swapAmount_ = amount_ * 775 / 1000;
        uint256 swappedUAmount_ = _swapXToUSDT(swapAmount_, address(this));

        uint256 toLpAmount_ = swappedUAmount_ * 225 / 775;
        uint256 toBonusAmount_ = swappedUAmount_ * 50 / 775;
        uint256 liquidity_ = _addLiquidityAndBurn(toLpAmount_, amount_ - swapAmount_, amount_);
        _addPowerWithSell(user_, toLpAmount_ * 2, amount_ - swapAmount_, liquidity_);

        IERC20Token(USDT).safeTransfer(user_, swappedUAmount_ - toBonusAmount_ - toLpAmount_);

        IERC20Token(USDT).safeTransfer(BONUSPOOL, toBonusAmount_);
        IBonusPool(BONUSPOOL).allotBonusFromLP(toBonusAmount_);
        emit EventSellXTOKEN(user_, amount_, swapAmount_, swappedUAmount_, toLpAmount_, liquidity_, toBonusAmount_);
    }

    function _addPowerWithSell(address user_, uint256 amount_, uint256 xAmount_, uint256 liquidity_) internal {
        uint256 power_ = amount_ * dayPower / 10**18;
        usersLpPower[user_] += power_;
        totalLpPower += power_;
        emit EventStake(user_, amount_, power_, liquidity_, amount_ / 2, xAmount_, block.timestamp);
    }

    function addStakeLPPower(uint256 amount_, address user_) external onlyNFTPresell checkDayId updateRewards(user_) {
        uint256 power_ = amount_ * dayPower / 10**18;
        usersLpPower[user_] += power_;
        totalLpPower += power_;

        emit EventStakeWithNFT(user_, amount_, power_, block.timestamp);
    }

    function notifyRewards(uint256 amount_) external onlyBonusPool {
        uint256 rewardPerStoredNew_ = rewardPerStored;
        uint256 totalLpPower_ = totalLpPower;
        if (totalLpPower_ > 0) {
            rewardPerStoredNew_ += amount_ * _PRECISION / totalLpPower_;
            rewardPerStored = rewardPerStoredNew_;
        }
        totalReward += amount_;

        emit EventNotifyLPReward(amount_, rewardPerStoredNew_, totalLpPower_);
    }

    function setCheckTime(uint256 time_) public onlyManager {
        checkTime = time_;
    }

    function _toLock() internal {
        _unlocked = 0;
    }

    function _toUnlock() internal {
        _unlocked = 1;
    }

    function _checkUser(address user_) internal view {
        require(COMMUNITY.referrerOf(UID, user_) != address(0), "No referrer");
    }

    function _getRouteFromToken(address fromToken_, address toToken_, bool isStable_) internal view returns (IRouter.Route memory) {
        return IRouter.Route({
            from: fromToken_,
            to: toToken_,
            stable: isStable_,
            factory: SWAPFACTORY
        });
    }

    function _updateRewards(address user_) internal {
        if (user_ == address(0)) return;
        if (userRewardPerStored[user_] == rewardPerStored) return;
        uint256 rewardNew_ = earnedNew(user_);
        if (rewardNew_ > 0) {
            userRewards[user_] += rewardNew_;
        }
        userRewardPerStored[user_] = rewardPerStored;
    }

    function _swapUSDTToX(uint256 amount_, address recipient_) internal returns (uint256){
        IRouter.Route[] memory route_ = new IRouter.Route[](1);
        route_[0] = _getRouteFromToken(USDT, XTOKEN, false);
        uint256 minAmount_ = _getTokenPrice(JLP_USDT_X, USDT, amount_) * 97 / 100;
        uint256[] memory amounts_ = IRouter(SWAPROUTER).swapExactTokensForTokens(amount_, minAmount_, route_, recipient_, block.timestamp);
        return amounts_[amounts_.length - 1];
    }

    function _swapXToUSDT(uint256 amount_, address recipient_) internal returns (uint256){
        IRouter.Route[] memory route_ = new IRouter.Route[](1);
        route_[0] = _getRouteFromToken(XTOKEN, USDT, false);
        uint256 minAmount_ = _getTokenPrice(JLP_USDT_X, XTOKEN, amount_) * 97 / 100;
        uint256[] memory amounts_ = IRouter(SWAPROUTER).swapExactTokensForTokens(amount_, minAmount_, route_, recipient_, block.timestamp);
        return amounts_[amounts_.length - 1];
    }

    function _addLiquidity(uint256 uAmount_, uint256 tokenAmount_) internal returns(uint256) {
        (, uint256 costX_, uint256 liquidity_) = IRouter(SWAPROUTER).addLiquidity(
            USDT,
            XTOKEN,
            false,
            uAmount_,
            tokenAmount_,
            0,
            0,
            BLACK_HOLE,
            block.timestamp
        );

        if (costX_ < tokenAmount_) {
            IERC20Token(XTOKEN).safeTransfer(JLP_USDT_X, tokenAmount_ - costX_);
            IPool(JLP_USDT_X).sync();
        }
        return liquidity_;
    }

    function _addLiquidityAndBurn(uint256 uAmount_, uint256 tokenAmount_, uint256 burnAmount_) internal returns(uint256) {
        (, uint256 costX_, uint256 liquidity_) = IRouter(SWAPROUTER).addLiquidity(
            USDT,
            XTOKEN,
            false,
            uAmount_,
            tokenAmount_,
            0,
            0,
            BLACK_HOLE,
            block.timestamp
        );
        if (costX_ < tokenAmount_) {
            IERC20Token(XTOKEN).safeTransfer(JLP_USDT_X, tokenAmount_ - costX_);
        }
        IERC20TokenX(XTOKEN).burnFromJLP(burnAmount_);
        return liquidity_;
    }

    function _getTokenPrice(address lp_, address tokenIn_, uint256 amount_) internal view returns (uint256) {
        address token0 = IPool(lp_).token0();
        (uint256 reserveA, uint256 reserveB, ) = IPool(lp_).getReserves();
        return tokenIn_ == token0 ? amount_ * reserveB / reserveA : amount_ * reserveA / reserveB;
    }

    function _checkDayId() internal {
        if (block.timestamp >= checkTime + 86400) {
            dayId++;
            dayPower = dayPower * POWER_GROWTH / 100; // 2%
            checkTime += 86400;
            emit EventDayPowerUpdate(dayPower, dayId, block.timestamp);
        }
    }

    function _onlyRootManager() internal view {
        if(!hasRole(ROOT_MANAGER, msg.sender)) revert ErrorCaller();
    }

    event EventStake(
        address indexed user,
        uint256 amount,
        uint256 addPower,
        uint256 liquidity,
        uint256 lpUAmount,
        uint256 lpXAmount_,
        uint256 time
    );

    event EventStakeWithNFT(
        address indexed user,
        uint256 amount,
        uint256 addPower,
        uint256 time
    );
    event EventSellXTOKEN(
        address indexed user,
        uint256 amount,
        uint256 swapAmount,
        uint256 swappedUAmount,
        uint256 toLpAmount,
        uint256 liqudity,
        uint256 toBonusAmount
    );
    event EventNotifyLPReward(uint256 amount, uint256 rewardPerStoredNew, uint256 totalLpPower);
    event EventClaimReward(address indexed user, uint256 reward_, uint256 totalClaimed);
    event EventDayPowerUpdate(uint256 dayPower, uint256 dayId, uint256 timestamp);
}