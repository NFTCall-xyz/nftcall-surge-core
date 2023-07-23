// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {OptionType, PositionState} from "./IOptionToken.sol";

enum TradeType {
    OPEN,
    CLOSE
}

struct Strike {
    uint256 spotPrice;
    uint256 strikePrice;
    uint256 duration;
    uint256 expiry;
}

interface IVault {
    struct CollectionConfiguration {
        bool paused;
        bool activated;
        uint32 id;
        uint32 weight; // percentage: 1000000 means 100%
        address optionToken;
    }

    event CreateStrike(uint256 indexed strikeId, uint256 duration, uint256 expiration, uint256 spotPrice, uint256 strikePrice);
    event DestoryStrike(uint256 indexed strikeId);
    event OpenPosition(address indexed collection, uint256 indexed strikeId, uint256 indexed positionId, uint256 estimatedPremium);
    event ReceivePremium(address indexed user, uint256 amountToReserve, uint256 amountToLiquidityPool);
    event SendRevenue(address indexed receiver, uint256 amount, uint256 fee);
    event CreateMarket(address indexed collection, uint32 weight, address optionToken);
    event KeeperAddressUpdated(address indexed keeperAddress);

    function keeper() external view returns(address);
    function setKeeper(address keeperAddress) external;
    function reserve() external view returns(address);
    function unrealizedPNL() external view returns(int256);
    function updateUnrealizedPNL() external returns(int256);
    function unrealizedPremium() external view returns(uint256);
    function deposit(uint256 amount, address onBehalfOf) external;
    function withdraw(uint256 amount, address to) external returns(uint256);
    function totalAssets() external view returns(uint256);
    function totalLockedAssets() external view returns(uint256);
    function openPosition(address collection, address onBehalfOf, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) external returns(uint256 positionId, uint256 premium);
    function activePosition(address collection, uint256 positionId) external returns(uint256 premium);
    function closePosition(address collection, uint256 positionId) external returns(uint256);
    function forceClosePendingPosition(address collection, uint256 positionId) external;
    function strike(uint256 strikeId) external view returns(Strike memory);
    function addMarket(address collection, uint32 weight, address optionToken) external returns(uint32);
    function markets() external view returns(address[] memory);
    function marketConfiguration(address collection) external view returns(CollectionConfiguration memory);
    function maximumOptionAmount(address collection, OptionType optionType) external view returns(uint256);

    error ZeroAmount(address thrower);
    error InvalidStrikePrice(address thrower, uint strikePrice, uint spotPrice);
    error InvalidDuration(address thrower, uint duration);
    error InsufficientLiquidityForCollection(address thrower, address collection, uint256 totalLockedAssets, uint256 amountToBeLocked, uint256 vaultLiquidity);
    error InsufficientLiquidity(address thrower, uint256 totalLockedAssets, uint256 amountToBeLocked, uint256 vaultLiquidity);
    error InvalidStrikeId(address thrower, uint256 strikeId);
    error PremiumTransferFailed(address thrower, address sender, address receiver, uint256 premium);
    error PositionNotActive(address thrower, uint256 positionId, PositionState state);
    error PositionNotExpired(address thrower, uint256 positionId, uint256 expiry, uint256 blockTimestamp);
    error RevenueTransferFailed(address thrower, address receiver, uint256 revenue);
    error CollectionAlreadyExists(address thrower, address collection);
    error OnlyKeeper(address thrower, address caller, address keeper);
}

