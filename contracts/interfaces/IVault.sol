// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {OptionType} from "./IOptionToken.sol";

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
    function unrealizedPNL() external view returns(int256);
    function unrealizedPremium() external view returns(uint256);
    function deposit(uint256 amount, address onBehalfOf) external;
    function withdraw(uint256 amount, address to) external returns(uint256);
    function totalAssets() external view returns(uint256);
    function totalLockedAssets() external view returns(uint256);
    function openPosition(address collection, address onBehalfOf, OptionType optionType, uint8 strikePriceIdx, uint8 durationIdx, uint256 amount) external returns(uint256 positionId, uint256 premium);
    function activatePosition(address collection, uint256 positionId) external returns(uint256 premium);
    function closePosition(address collection, address to, uint256 positionId) external returns(uint256);
    function forceClosePendingPosition(address collection, uint256 positionId) external;
    function strike(uint256 strikeId) external view returns(Strike memory);
}