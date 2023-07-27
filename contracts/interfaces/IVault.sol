// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {OptionType, PositionState} from "./IOptionToken.sol";

enum TradeType {
    OPEN,
    CLOSE
}

struct Strike {
    uint256 entryPrice;
    uint256 strikePrice;
    uint256 duration;
    uint256 expiry;
}

interface IVault {
    struct CollectionConfiguration {
        bool frozen;
        bool activated;
        uint32 id;
        uint32 weight; // percentage: 1000000 means 100%
        address optionToken;
    }

    event CreateStrike(uint256 indexed strikeId, uint256 duration, uint256 expiration, uint256 entryPrice, uint256 strikePrice);
    event DestoryStrike(uint256 indexed strikeId);
    event CreateMarket(address indexed collection, uint32 weight, address optionToken);
    event KeeperAddressUpdated(address indexed keeperAddress);
    event UpdateLPTokenPrice(address indexed lpToken, uint256 newPrice);
    event PauseVault(address indexed operator);
    event UnpauseVault(address indexed operator);
    event FreezeMarket(address indexed operator, address indexed collection);
    event DefreezeMarket(address indexed operator, address indexed collection);
    event ActivateMarket(address indexed operator, address indexed collection);
    event DeactivateMarket(address indexed operator, address indexed collection);

    struct OpenPositionEventParameters {
        OptionType optionType;
        uint256 expiration;
        uint256 entryPrice;
        uint256 strikePrice;
        uint256 amount;
        uint256 premium;
        uint256 keeperFee;
    }

    event OpenPosition(address caller, address indexed receiver, address indexed collection, uint256 indexed positionId, OpenPositionEventParameters parameters);
    event ActivatePosition(address indexed owner, address indexed collection, uint256 indexed positionId, uint256 premium, uint256 excessPremium, int256 delta);
    event ExercisePosition(address indexed owner, address indexed collection, uint256 indexed positionId, uint256 revenue, uint256 exerciseFee, uint256 settlementPrice);
    event ExpirePosition(address indexed owner, address indexed collection, uint256 indexed positionId, uint256 settlementPrice);
    event CancelPosition(address indexed owner, address indexed collection, uint256 indexed positionId, uint256 returnedPremium);
    event FailPosition(address indexed owner, address indexed collection, uint256 indexed positionId, uint256 returnedPremium);
    event SendAssetsToLPToken(address indexed operator, uint256 amount);
    event UpdateMinimumAnnualRateOfReturnOnLockedAssets(address indexed operator, uint256 ratio);

    function KEEPER_FEE() external view returns(uint256);
    function RESERVE_RATIO() external view returns(uint256);
    function MAXIMUM_LOCK_RATIO() external view returns(uint256);
    function MAXIMUM_CALL_STRIKE_PRICE_RATIO() external view returns(uint256);
    function MAXIMUM_PUT_STRIKE_PRICE_RATIO() external view returns(uint256);
    function MINIMUM_CALL_STRIKE_PRICE_RATIO() external view returns(uint256);
    function MINIMUM_PUT_STRIKE_PRICE_RATIO() external view returns(uint256);
    function MAXIMUM_DURATION() external view returns(uint256);
    function MINIMUM_DURATION() external view returns(uint256);
    function TIME_SCALE() external view returns(uint256);
    
    function keeper() external view returns(address);
    function setKeeper(address keeperAddress) external;
    function reserve() external view returns(address);
    function backstopPool() external view returns(address);
    function unrealizedPNL() external view returns(int256);
    function updateUnrealizedPNL() external returns(int256);
    function updateCollectionRisk(address collection, int256 delta, int256 PNL) external;
    function unrealizedPremium() external view returns(uint256);
    function deposit(uint256 amount, address onBehalfOf) external;
    function withdraw(uint256 amount, address to) external returns(uint256);
    function redeem(uint256 amount, address to) external returns(uint256);
    function totalAssets() external view returns(uint256);
    function totalLockedAssets() external view returns(uint256);
    function estimatePremium(address collection, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) external view returns(uint256 premium);
    function minimumAnnualRateOfReturnOnLockedAssets() external view returns(uint256);
    function setMinimumAnnualRateOfReturnOnLockedAssets(uint256 ratio) external;
    function adjustedVolatility(address collection, OptionType optionType, uint256 strikePrice, uint256 amount) external view returns(uint256);
    function openPosition(address collection, address onBehalfOf, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount, uint256 maximumPremium) external returns(uint256 positionId, uint256 premium);
    function activatePosition(address collection, uint256 positionId) external returns(uint256 premium, int256 delta);
    function positionPNLWeightedDelta(address collection, uint256 positionId) external view returns(int256 unrealizePNL, int256 weightedDelta);
    function closePosition(address collection, uint256 positionId) external returns(uint256);
    function forceClosePendingPosition(address collection, uint256 positionId) external;
    function strike(uint256 strikeId) external view returns(Strike memory);
    function addMarket(address collection, uint32 weight, address optionToken) external returns(uint32);
    function markets() external view returns(address[] memory);
    function marketConfiguration(address collection) external view returns(CollectionConfiguration memory);
    function maximumOptionAmount(address collection, OptionType optionType) external view returns(uint256);
    function minimumPremium(OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) external view returns(uint256);
    function pause() external;
    function unpause() external;
    function isPaused() external view returns(bool);
    function freezeMarket(address collection) external;
    function defreezeMarket(address collection) external;
    function isFrozenMarket(address collection) external view returns(bool);
    function activateMarket(address collection) external;
    function deactivateMarket(address collection) external;
    function isActiveMarket(address collection) external view returns(bool);
    function feeRatio() external view returns(uint256);
    function profitFeeRatio() external view returns(uint256);
    function collectUntitledAssetsFromLPToken(address receiver) external returns(uint256);
    function sendAssetsToLPToken(uint256 amount) external;

    error ZeroAmount(address thrower);
    error InvalidStrikePrice(address thrower, uint strikePrice, uint entryPrice);
    error InvalidDuration(address thrower, uint duration);
    error InsufficientLiquidityForCollection(address thrower, address collection, uint256 totalLockedAssets, uint256 amountToBeLocked, uint256 vaultLiquidity);
    error InsufficientLiquidity(address thrower, uint256 totalLockedAssets, uint256 amountToBeLocked, uint256 vaultLiquidity);
    error InvalidStrikeId(address thrower, uint256 strikeId);
    error PremiumTooHigh(address thrower, uint256 positionId, uint256 premium, uint256 maximumPremium);
    error PremiumTransferFailed(address thrower, address sender, address receiver, uint256 premium);
    error PositionNotActive(address thrower, uint256 positionId, PositionState state);
    error PositionNotExpired(address thrower, uint256 positionId, uint256 expiry, uint256 blockTimestamp);
    error RevenueTransferFailed(address thrower, address receiver, uint256 revenue);
    error CollectionAlreadyExists(address thrower, address collection);
    error OnlyKeeper(address thrower, address caller, address keeper);
    error OnlyUnpaused(address thrower, address caller);
    error FrozenMarket(address thrower, address collection);
    error DeactivatedMarket(address thrower, address collection);
    error OnlyKeeperOrOwnerOrPayer(address thrower, address caller, address keeper, address owner, address payer);
}

