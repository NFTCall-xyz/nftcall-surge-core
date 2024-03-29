// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

enum OptionType {
    LONG_CALL,
    LONG_PUT
}

enum PositionState {
    EMPTY,
    PENDING,
    ACTIVE,
    CLOSED
}

struct OptionPosition {
    PositionState state;
    OptionType optionType;
    address payer;
    uint256 strikeId;
    uint256 amount;
    uint256 premium;
    uint256 maximumPremium;
}

interface IOptionToken {
    
    event Initialize(address indexed vault);
    event UpdateBaseURI(string baseURI);
    event OpenPosition(address payer, address indexed to, uint256 indexed positionId, OptionType optionType, uint256 strikeId, uint256 amount, uint256 maximumPremium);
    event ActivePosition(uint256 indexed positionId, uint256 premium);
    event ClosePosition(uint256 indexed positionId);
    event ForceClosePosition(uint256 indexed positionId);
    
    function vault() external view returns(address);
    function setBaseURI(string memory baseURI) external;
    function openPosition(address payer, address to, OptionType optionType, uint256 strikeId, uint256 amount, uint256 maximumPremium) external returns(uint256 positionId);
    function activePosition(uint256 positionId, uint256 premium) external;
    function closePosition(uint256 positionId) external;
    function forceClosePendingPosition(uint256 positionId) external;
    function optionPositionState(uint256 positionId) external view returns(PositionState);
    function optionPosition(uint256 positionId) external view returns(OptionPosition memory);
    function lockedValue(uint256 positionId) external view returns(uint256);
    function totalValue() external view returns(uint256);
    function totalValue(OptionType) external view returns(uint256);
    function totalAmount() external view returns(uint256);
    function totalAmount(OptionType) external view returns(uint256);

    error OnlyVault(address thrower, address caller, address vault);
    error ZeroVaultAddress(address thrower);
    error ZeroAmount(address thrower);
    error IsNotPending(address thrower, uint256 positionId, PositionState state);
    error IsNotActive(address thrower, uint256 positionId, PositionState state);
    error NonexistentPosition(address thrower, uint256 positionId);
}