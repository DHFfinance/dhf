// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ISwapRouter, ISwapFactory} from "./interfaces/token/ISwapRouter.sol";
import {IPoolFactory} from "./interfaces/jswap/IPoolFactory.sol";
import {IPool} from "./interfaces/jswap/IPool.sol";
import {IBonusPool} from "./interfaces/IBonusPool.sol";


contract TokenX is ERC20, ERC20Permit, AccessControl {
    address public constant BLACK_HOLE =
        0x000000000000000000000000000000000000dEaD;
    bytes32 public constant INTERN_SYSTEM_MANAGER =
        keccak256("INTERN_SYSTEM_MANAGER");
    bytes32 public constant INTERN_SYSTEM = keccak256("INTERN_SYSTEM");
    bytes32 public constant TOKEN_MANAGER = keccak256("TOKEN_MANAGER");
    bytes32 public constant JINTERN_SYSTEM = keccak256("JINTERN_SYSTEM");

    ISwapRouter public constant SWAPROUTER =
        ISwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IPoolFactory public constant JSWAPFACTORY =
        IPoolFactory(0xb61bCd0Aaefc08E7627d269345548a8339957545);
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public immutable BONUSPOOL;
    address public immutable STAKEPOOL;

    address public immutable LP_TOKEN_BNB;
    address public jLpXUSDT;

    uint256 public feeRatio = 3e3;
    uint256 public lastDay;
    uint256 public feeAmount;
    uint256 public minFeeAmount = 1e23;
    bool public isLimit = true;

    error ErrorCallerNotManager();
    error ErrorAddressZero();
    error ErrorFailureTransfer();
    error ErrorTransfer();
    error ErrorCaller();
    error ErrorInsufficientBalance();

    modifier onlyTokenManager() {
        if (!hasRole(TOKEN_MANAGER, msg.sender)) revert ErrorCallerNotManager();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address bonusPool_,
        address stakePool_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (
            bonusPool_ == address(0)
            || stakePool_ == address(0)
        ) revert ErrorAddressZero();

        _setRoleAdmin(JINTERN_SYSTEM, INTERN_SYSTEM_MANAGER);
        _setRoleAdmin(INTERN_SYSTEM, INTERN_SYSTEM_MANAGER);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TOKEN_MANAGER, msg.sender);
        _grantRole(JINTERN_SYSTEM, msg.sender);
        _grantRole(INTERN_SYSTEM, msg.sender);
        _grantRole(INTERN_SYSTEM, bonusPool_);
        _grantRole(INTERN_SYSTEM, address(this));

        BONUSPOOL = bonusPool_;
        STAKEPOOL = stakePool_;

        address factory_ = SWAPROUTER.factory();
        LP_TOKEN_BNB = ISwapFactory(factory_).createPair(address(this), WBNB);

        super._approve(address(this), address(SWAPROUTER), type(uint256).max);

        lastDay = block.timestamp / 86400;
        ignoreList[LP_TOKEN_BNB] = true;
        ignoreList[bonusPool_] = true;
        ignoreList[stakePool_] = true;
        ignoreList[address(this)] = true;
        ignoreList[BLACK_HOLE] = true;

        _mint(msg.sender, 2100 * 1e8 * 1e18);
    }

    receive() external payable {}

    function mining() external {
        if (!isLimit) return;
        _mining();
    }

    function setJLP() external onlyTokenManager {
        address lp_ = JSWAPFACTORY.createPool(address(this), USDT, false);
        jLpXUSDT = lp_;
        ignoreList[lp_] = true;
        ignoreList[IPool(lp_).poolFees()] = true;
    }

    function setLastDay(uint256 time_) external onlyTokenManager {
        lastDay = time_ / 86400;
    }

    function setFeeRatio(uint256 ratio_) external onlyTokenManager {
        feeRatio = ratio_;
    }

    function setMinFeeAmount(uint256 value_) external onlyTokenManager {
        minFeeAmount = value_;
    }

    function setIsLimit(bool value_) external onlyTokenManager {
        isLimit = value_;
    }

    function rescueToken(address token_, uint256 amount_) external onlyTokenManager {
        uint256 balance_ = address(this).balance;
        if (balance_ > 0) {
            (bool success_, ) = msg.sender.call{value: balance_}("");
            if (!success_) {
                revert ErrorFailureTransfer();
            }
        }
        if (token_ != address(this)) {
            IERC20(token_).transfer(msg.sender, amount_);
        }
    }

    function allotFee() external onlyTokenManager {
        _allotFee();
    }

    function burnFromJLP(uint256 amount_) external {
        if (msg.sender != STAKEPOOL) revert ErrorCaller();
        uint256 balance_ = this.balanceOf(jLpXUSDT);
        if (balance_ < amount_) revert ErrorInsufficientBalance();
        super._transfer(jLpXUSDT, BLACK_HOLE, amount_);
        IPool(jLpXUSDT).sync();
    }

    function _transfer(
        address sender_,
        address recipient_,
        uint256 amount_
    ) internal override {
        if (!isLimit) {
            super._transfer(sender_, recipient_, amount_);
            return;
        }
        if (sender_ == jLpXUSDT) {
            if (!hasRole(JINTERN_SYSTEM, recipient_)) revert ErrorTransfer();
        } else if (recipient_ == jLpXUSDT) {
            if (!hasRole(JINTERN_SYSTEM, sender_)) revert ErrorTransfer();
        } else if (sender_ == LP_TOKEN_BNB || recipient_ == LP_TOKEN_BNB){
            bool _senderIs = hasRole(INTERN_SYSTEM, sender_);
            bool _recipientIs = hasRole(INTERN_SYSTEM, recipient_);

            if (!(_senderIs || _recipientIs)) {
                uint256 feeAmtAdd_ = (amount_ * feeRatio) / 100e3;
                super._transfer(sender_, address(this), feeAmtAdd_);
                amount_ -= feeAmtAdd_;
                feeAmount += feeAmtAdd_;
                if (recipient_ == LP_TOKEN_BNB) {
                    _allotFee();
                }
                emit EventToFee(sender_, recipient_, feeAmtAdd_);
            }
            _mining();
        } else {
            if (!(hasRole(INTERN_SYSTEM, sender_) || hasRole(INTERN_SYSTEM, recipient_))){
                _mining();
            }
        }
        super._transfer(sender_, recipient_, amount_);
    }

    function _mining() internal {
        uint256 nowDay_ = block.timestamp / 86400;
        if (nowDay_ > lastDay) {
            lastDay = nowDay_;
            uint256 balance_ = this.balanceOf(jLpXUSDT);
            if (balance_ > 0) {
                uint256 amount_ = balance_ / 100;
                super._transfer(jLpXUSDT, BONUSPOOL, amount_);
                IPool(jLpXUSDT).sync();

                IBonusPool(BONUSPOOL).mining(amount_);
                if (balance_ - amount_ <= 2100*1e22) {
                    isLimit = false;
                }
                emit EventToMining(BONUSPOOL, balance_, amount_, isLimit);
            }
        }
    }

    function _allotFee() internal {
        uint256 feeAmount_ = feeAmount;
        if(feeAmount_ < minFeeAmount) {
            return;
        }
        feeAmount = 0;
        uint256 burnAmount_ = feeAmount_ * 2 / 30;
        super._transfer(address(this), BLACK_HOLE, burnAmount_);
        uint256 bValue_ = _swapToNative(feeAmount_ - burnAmount_, address(this));
        _toBonus(bValue_ * 5 / 28);
        IBonusPool(BONUSPOOL).allotBonus{value: bValue_}(bValue_);

        emit EventAllotFee(block.timestamp, feeAmount_, burnAmount_, bValue_);
    }

    function _toBonus(uint256 amount_) internal {
        uint256 totalSupply_ = bonusTotalSupply();
        if (totalSupply_ == 0) {
            return;
        }
        uint256 ratio_ = (amount_ * 1e18) / totalSupply_;
        uint256 index_ = index;
        if (ratio_ > 0) {
            index_ += ratio_;
            index = index_;
        }
        emit EventToHoldBonus(amount_, ratio_, index_, totalSupply_);
    }

    function bonusTotalSupply() public view returns(uint256) {
        return totalSupply()
            - this.balanceOf(jLpXUSDT)
            - this.balanceOf(LP_TOKEN_BNB)
            - this.balanceOf(BLACK_HOLE)
            - this.balanceOf(BONUSPOOL);
    }

    function _swapToNative(
        uint256 amount_,
        address recipient_
    ) internal returns (uint256) {
        address[] memory path_ = new address[](2);
        path_[0] = address(this);
        path_[1] = WBNB;

        uint256 valueBefore_ = recipient_.balance;
        uint256 minAmount_ = _getTokenPrice(LP_TOKEN_BNB, address(this), amount_) * 94 / 100;
        SWAPROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount_,
            minAmount_,
            path_,
            recipient_,
            block.timestamp
        );
        return recipient_.balance - valueBefore_;
    }

    function _getTokenPrice(address lp_, address tokenIn_, uint256 amount_) internal view returns (uint256) {
        address token0 = IPool(lp_).token0();
        (uint256 reserveA, uint256 reserveB, ) = IPool(lp_).getReserves();
        return tokenIn_ == token0 ? amount_ * reserveB / reserveA : amount_ * reserveA / reserveB;
    }

    uint256 public index;
    mapping(address => uint256) public supplyIndex;
    mapping(address => uint256) public claimables;
    mapping(address => bool) public ignoreList;

    function getBonusInfo(
        address recipient_
    )
        external
        view
        returns (uint256 index_, uint256 supplyIndex_, uint256 claimables_)
    {
        index_ = index;
        supplyIndex_ = supplyIndex[recipient_];
        claimables_ = claimables[recipient_];
        uint256 supplied_ = balanceOf(recipient_);
        if (supplied_ > 0) {
            uint256 delta_ = index_ - supplyIndex_;
            if (delta_ > 0) {
                claimables_ =
                claimables[recipient_] +
                (supplied_ * delta_) /
                1e18;
            }
        }
    }

    function updateUser(address user_) external {
        if (msg.sender != BONUSPOOL) revert ErrorCaller();
        _updateFor(user_);
    }

    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256
    ) internal override {
        if (from_ == address(0)) return;
        _updateIndex(from_, to_);
    }

    function _updateIndex(address from_, address to_) internal {
        _updateFor(from_);
        _updateFor(to_);
    }

    function _updateFor(address recipient_) internal {
        if (ignoreList[recipient_]) {
            return;
        }
        uint256 supplied_ = balanceOf(recipient_);
        if (supplied_ > 0) {
            uint256 supplyIndex_ = supplyIndex[recipient_];
            uint256 index_ = index;
            if (supplyIndex_ == index_) {
                return;
            }
            supplyIndex[recipient_] = index_;
            uint256 delta_ = index_ - supplyIndex_;
            if (delta_ > 0) {
                uint256 _share = (supplied_ * delta_) / 1e18;
                claimables[recipient_] += _share;
            }
        } else {
            supplyIndex[recipient_] = index;
        }
    }

    event EventToFee(address sender, address recipient, uint256 feeAmtAdd);
    event EventToMining(address lp, uint256 lpBalance, uint256 amount, bool isLimit);
    event EventAllotFee(uint256 allotTime, uint256 amount, uint256 burnAmount, uint256 allotBAmount);
    event EventToHoldBonus(uint256 toBonusAmount, uint256 ratio, uint256 index, uint256 totalSupply);

}
