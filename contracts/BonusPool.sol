// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20Token} from "./interfaces/IERC20Token.sol";
import {IStakePool} from "./interfaces/IStakePool.sol";
import {INFTPresell} from "./interfaces/INFTPresell.sol";
import {IERC20TokenX} from "./interfaces/IERC20TokenX.sol";
import {EmptyContract} from "./EmptyContract.sol";

contract BonusPool is EmptyContract {
    using SafeERC20Upgradeable for IERC20Token;

    uint256 public constant CLAIM_MIN_HOLD = 100 * 1e22;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    bytes32 public constant ROOT_MANAGER = keccak256("ROOT_MANAGER");
    uint256 public constant UID = 1;
    uint256 internal constant _RATE = 100;
    uint256 internal constant _ALLOT_RATE = 70;
    uint256 internal constant _LPSTAKE_RATE = 50; // 70*0.5
    uint256 internal constant _NFT_RATE = 5; // 70*0.05
    uint256 internal constant _MARKET_RATE = 10; // foundation+technology

    address public immutable XTOKEN;
    address public immutable USDT;
    address public immutable STAKEPOOL;
    address public immutable NFTPRESELL;
    address public immutable TOKEN_MARKET;
    address public immutable MARKET;
    address public immutable FOUNDARION_WALLET;
    address public immutable TECHNOLOGY_WALLET;

    mapping(address => mapping(uint256 => bool)) public userClaimedState;
    mapping(address => uint256) public merkleClaimedAmounts;
    MerkleData public merkleData;

    struct MerkleData {
        bytes32 merkleRoot;
        uint256 merkleVersion;
        uint256 merkleTotalReward;
        uint256 nextMerkleUpdateTime;
        uint256 merkleTotalClaimed;
    }

    mapping(address => uint256) public userClaimed;
    uint256 public totalHoldBonus;
    uint256 public totalHoldClaimed;

    error ErrorCallerNot();
    error ErrorCallerNotRootManager();
    error ErrorAddressZero();
    error ErrorAlreadyClaimed();
    error ErrorClaimedEpoch();
    error ErrorInvalidProof();
    error ErrorMerkleRootEmpty();
    error ErrorRewardAmount();
    error ErrorVersionNumber();
    error ErrorClaimExceed();
    error ErrorHoldTooLittle();
    error ErrorNoClaimable();
    error ErrorFailTransferNative();

    modifier onlyRootManager() {
        if (!hasRole(ROOT_MANAGER, msg.sender)) revert ErrorCallerNotRootManager();
        _;
    }

    modifier onlyToken() {
        if (msg.sender != XTOKEN) revert ErrorCallerNot();
        _;
    }

    modifier onlyNFTPresell() {
        if (msg.sender != NFTPRESELL) revert ErrorCallerNot();
        _;
    }

    modifier onlyStakePool() {
        if (msg.sender != STAKEPOOL) revert ErrorCallerNot();
        _;
    }

    receive() external payable {}

    /* ======== INITIALIZATION ======== */
    constructor(
        address XTOKEN_,
        address USDT_,
        address STAKEPOOL_,
        address NFTPRESELL_,
        address TOKEN_MARKET_,
        address MARKET_,
        address FOUNDARION_WALLET_,
        address TECHNOLOGY_WALLET_
    ) {
        if (XTOKEN_ == address(0)
            || USDT_ == address(0)
            || STAKEPOOL_ == address(0)
            || NFTPRESELL_ == address(0)
            || TOKEN_MARKET_ == address(0)
            || MARKET_ == address(0)
            || FOUNDARION_WALLET_ == address(0)
            || TECHNOLOGY_WALLET_ == address(0)
        ) revert ErrorAddressZero();

        XTOKEN = XTOKEN_;
        USDT = USDT_;
        STAKEPOOL = STAKEPOOL_;
        NFTPRESELL = NFTPRESELL_;
        MARKET = MARKET_;
        TOKEN_MARKET = TOKEN_MARKET_;
        FOUNDARION_WALLET = FOUNDARION_WALLET_;
        TECHNOLOGY_WALLET = TECHNOLOGY_WALLET_;

    }

    function reinitialize(address rootWallet_) public onlyManager reinitializer(2) {
        _grantRole(ROOT_MANAGER, rootWallet_);
    }

    function getRewardInfo(
        address user_
    ) external view returns (uint256) {
        return _getClaim(user_);
    }

    function claimHold() external {
        address user_ = msg.sender;
        if (IERC20TokenX(XTOKEN).balanceOf(user_) < CLAIM_MIN_HOLD)
            revert ErrorHoldTooLittle();

        IERC20TokenX(XTOKEN).updateUser(user_);

        (uint256 index_, , uint256 claimablesTotal_) = IERC20TokenX(XTOKEN).getBonusInfo(user_);
        if (claimablesTotal_ <= userClaimed[user_]) revert ErrorNoClaimable();
        uint256 claimables_ = claimablesTotal_ - userClaimed[user_];
        if (totalHoldClaimed + claimables_ > totalHoldBonus) revert ErrorClaimExceed();

        userClaimed[user_] = claimablesTotal_;
        totalHoldClaimed += claimables_;

        _transferNative(user_, claimables_);

        emit EventClaimHoldBonus(user_, claimables_, index_);
    }

    function claim(
        uint256 totalAmount_,
        bytes32[] calldata merkleProof_
    ) external {
        bytes32 root_ = merkleData.merkleRoot;
        if (root_ == "") revert ErrorMerkleRootEmpty();
        address account_ = msg.sender;
        uint256 claimedAmt_ = merkleClaimedAmounts[account_];
        if (claimedAmt_ >= totalAmount_) revert ErrorAlreadyClaimed();
        uint256 merkleVersion_ = merkleData.merkleVersion;
        if (userClaimedState[account_][merkleVersion_]) revert ErrorClaimedEpoch();

        {
            bytes32 leaf_ = keccak256(
                abi.encodePacked(account_, UID, totalAmount_)
            );
            bool isValidProof_ = MerkleProof.verifyCalldata(
                merkleProof_,
                root_,
                leaf_
            );
            if (!isValidProof_) revert ErrorInvalidProof();
        }
        uint256 reward_ = totalAmount_ - claimedAmt_;

        uint256 merkleTotalClaimed_ = merkleData.merkleTotalClaimed + reward_;
        if (merkleTotalClaimed_ > merkleData.merkleTotalReward) revert ErrorRewardAmount();
        merkleData.merkleTotalClaimed = merkleTotalClaimed_;
        merkleClaimedAmounts[account_] = totalAmount_;
        userClaimedState[account_][merkleVersion_] = true;

        IERC20Token(XTOKEN).safeTransfer(account_, reward_);

        emit EventClaim(account_, reward_, totalAmount_);
    }

    function mining(uint256 amount_) external onlyToken {
        uint256 allotAmount_ = amount_ * _ALLOT_RATE / _RATE;
        IERC20Token(XTOKEN).safeTransfer(BLACK_HOLE, amount_ - allotAmount_);

        //1
        uint256 lpStakeAmount_ = allotAmount_ * _LPSTAKE_RATE / _RATE;
        IStakePool(STAKEPOOL).notifyRewards(lpStakeAmount_);
        //4
        uint256 nftAmount_ = allotAmount_ * _NFT_RATE / _RATE;
        INFTPresell(NFTPRESELL).notifyNFTRewards(nftAmount_);
        // 67
        uint256 marketAmount_ = allotAmount_ * _MARKET_RATE / _RATE;
        IERC20Token(XTOKEN).safeTransfer(FOUNDARION_WALLET, marketAmount_/2);
        IERC20Token(XTOKEN).safeTransfer(TECHNOLOGY_WALLET, marketAmount_/2);

        emit EventMiningAllot(
            amount_,
            allotAmount_,
            allotAmount_ - lpStakeAmount_ - nftAmount_ - marketAmount_,
            lpStakeAmount_,
            nftAmount_,
            marketAmount_
        );
    }

    function allotBonus(uint256 amount_) external payable onlyToken {
        uint256 smallAmount_ = amount_ * 3 / 28; // 0.3%
        uint256 daoAmount_ = amount_ * 5 / 28; // 0.5%
        INFTPresell(NFTPRESELL).notifySwapFeeRewards(smallAmount_, daoAmount_);

        uint256 marketAmount_ = amount_ * 15 / 28; // 1.5%
        _transferNative(TOKEN_MARKET, marketAmount_);

        totalHoldBonus += amount_ * 5 / 28; // 0.5%

        emit EventAllotBonus(amount_, marketAmount_, smallAmount_, daoAmount_);
    }

    function allotBonusFromLP(uint256 amount_) external onlyStakePool {
        uint256 smallAmount_ = amount_ * 2 / 10; // 1%
        uint256 daoAmount_ = amount_ * 3 / 10; // 1.5%
        INFTPresell(NFTPRESELL).notifyTokenXSellRewards(smallAmount_, daoAmount_);

        uint256 marketAmount_ = amount_ - smallAmount_ - daoAmount_;
        IERC20Token(USDT).safeTransfer(MARKET, marketAmount_);

        emit EventAllotBonusFromLP(amount_, marketAmount_, smallAmount_, daoAmount_);
    }

    function sendLPReward(address user_, uint256 amount_) external onlyStakePool {
        IERC20Token(XTOKEN).safeTransfer(user_, amount_);
    }

    function sendNFTReward(address user_, uint256 amount_) external onlyNFTPresell {
        IERC20Token(XTOKEN).safeTransfer(user_, amount_);
    }

    function sendSwapFeeReward(address user_, uint256 amount_) external onlyNFTPresell {
        _transferNative(user_, amount_);
    }

    function sendSellReward(address user_, uint256 amount_) external onlyNFTPresell {
        IERC20Token(USDT).safeTransfer(user_, amount_);
    }

    function updateMerkleRoot(bytes32 merkleRoot_, uint256 merkleVersion_, uint256 newTotalReward_) external onlyRootManager {
        if (merkleRoot_ == "") revert ErrorMerkleRootEmpty();

        if (newTotalReward_ < merkleData.merkleTotalReward) revert ErrorRewardAmount();
        if (merkleVersion_ <= merkleData.merkleVersion) revert ErrorVersionNumber();

        merkleData.merkleRoot = merkleRoot_;
        uint256 addTotalReward_ = newTotalReward_ - merkleData.merkleTotalReward;
        merkleData.merkleTotalReward = newTotalReward_;
        merkleData.merkleVersion = merkleVersion_;

        emit EventUpdateMerkleRoot(merkleRoot_, merkleVersion_, newTotalReward_, addTotalReward_);
    }

    function setNextMerkleUpdateTime(uint256 time_) external onlyManager {
        merkleData.nextMerkleUpdateTime = time_;
    }

    function _transferNative(address user_, uint256 amount_) internal {
        (bool success_, ) = payable(user_).call{value: amount_}("");
        if (!success_) revert ErrorFailTransferNative();
    }

    function _getClaim(address user_) internal view returns (uint256) {
        (, , uint256 claimablesTotal_) = IERC20TokenX(XTOKEN).getBonusInfo(
            user_
        );
        if (claimablesTotal_ > userClaimed[user_]) {
            return claimablesTotal_ - userClaimed[user_];
        }
        return 0;
    }

    event EventClaim(address user, uint256 reward, uint256 totalAmount);
    event EventUpdateMerkleRoot(bytes32 merkleRoot, uint256 merkleVersion, uint256 newTotalReward, uint256 addReward);
    event EventMiningAllot(
        uint256 amount,
        uint256 allotAmount,
        uint256 teamAmount,
        uint256 lpStakeAmount,
        uint256 nftAmount,
        uint256 marketAmount
    );
    event EventAllotBonus(uint256 amount, uint256 marketAmount, uint256 smallAmount, uint256 daoAmount);
    event EventAllotBonusFromLP(uint256 amount, uint256 marketAmount, uint256 smallAmount, uint256 daoAmount);
    event EventClaimHoldBonus(
        address indexed user,
        uint256 claimable,
        uint256 index
    );
}
