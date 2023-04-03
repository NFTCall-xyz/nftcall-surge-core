// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/************
@title IPriceOracle interface
@notice Interface for the Aave price oracle.*/
interface IOracle {
  /***********
    @dev returns the asset price in wei
     */
  function getAssetPrice(address asset) external view returns (uint256);

  function getAssetPriceAndVol(address asset) external view returns (uint256 price, uint256 vol);

  function getPNL(address vault, address asset) external view returns(int256 pnl);

  function getDelta(address vault, address asset) external view returns(int256 delta);

  function getUpdateTimestampForVaultData(address vault) external view returns(uint256 timestamp);
}
