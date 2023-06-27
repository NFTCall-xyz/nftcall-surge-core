// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/************
@title IAssetRiskCache interface
@notice Interface for caching asset risks
*/
interface IAssetRiskCache {
  /***********
    @dev
     */
  function getAssetRisk(address asset) external view returns (int delta, int PNL);
  function getAssetDelta(address asset) external view returns (int delta);
  function updateAssetRisk(address asset, int delta, int PNL) external;
  function updateAssetDelta(address asset, int delta) external;
}
