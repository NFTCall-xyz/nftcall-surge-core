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
    uint256 strikeId;
    PositionState state;
    OptionType optionType;
    uint256 amount;
    uint256 premium;
}

interface IOptionToken {
    
    event Initialize(address indexed vault);
    event UpdateBaseURI(string baseURI);

    function vault() external view returns(address);
    function setBaseURI(string memory baseURI) external;
    function openPosition(OptionType optionType, address to, uint256 strikeId, uint256 amount) external returns(uint256 positionId);
    function activePosition(uint256 positionId, uint256 premium) external;
    function closePosition(uint256 positionId) external;
    function forceClosePosition(uint256 positionId) external;
    function optionPositionState(uint256 positionId) external view returns(PositionState);
    function optionPosition(uint256 positionId) external view returns(OptionPosition memory);
    function lockedValue(uint256 positionId) external view returns(uint256);
    function totalValue() external view returns(uint256);

    error OnlyVault(address thrower, address caller, address vault);
    error ZeroVaultAddress(address thrower);
    error ZeroAmount(address thrower);
    error IsNotPending(address thrower, uint256 positionId, PositionState state);
    error IsNotActive(address thrower, uint256 positionId, PositionState state);
}