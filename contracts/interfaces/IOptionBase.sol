// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IOptionBase {
    
    event OptionPositionOpened(address indexed to, uint256 indexed tokenId, uint8 strikePriceIndex, uint8 durationIndex, uint40 endTime, uint256 strikePrice, uint256 amount);
    event Mint(address indexed to, uint256 indexed tokenId);
    event Burn(address indexed owner, uint256 indexed tokenId);

    function mint(address to, uint8 strikePriceIndex, uint8 durationIndex, uint40 endTime, uint256 strikePrice, uint256 amount, uint256 tokenId) external;
    function burn(uint256 tokenId) external;

    function totalValue() external view returns(uint256);

}