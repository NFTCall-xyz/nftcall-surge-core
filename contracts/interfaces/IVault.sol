// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum TradeType {
    OPEN,
    CLOSE
}

struct Strike {
    uint256 spotPrice;
    uint256 strikePrice;
    uint256 expiry;
    uint256 premium;
}

interface IVault {
    function unrealizedPNL() external view returns(int256);
    function unrealizedPremium() external view returns(uint256);
    function deposit(uint256 amount, address onBehalfOf) external;
    function withdraw(uint256 amount, address to) external returns(uint256);
    function totalAssets() external view returns(uint256);
    function totalLockedAssets() external view returns(uint256);
    function openCallPosition(address collection, address onBehalfOf, uint8 strikePriceIdx, uint8 durationIdx, uint256 amount) external returns(uint256 positionId, uint256 premium);
    function activateCallPosition(address collection, uint256 positionId) external returns(uint256 premium);
    function closeCallPosition(address collection, address to, uint256 positionId) external returns(uint256);
    function openPutPosition(address collection, address to, uint8 strikePriceIdx, uint8 durationIdx, uint256 amount) external returns(uint256 positionId, uint256 permium);
    function activatePutPosition(address collection, uint256 positionId) external returns(uint256 premium);
    function closePutPosition(address collection, address to, uint256 positionId) external returns(uint256);
    function strike(uint256 strikeId) external view returns(Strike memory);
}