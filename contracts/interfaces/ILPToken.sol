// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface ILPToken {
    function mint(address onBehalfOf, uint256 amount) external;
    function burn(address user, address to, uint256 amount) external;
    function lockedBalanceOf(address user) external view returns(uint256);
}