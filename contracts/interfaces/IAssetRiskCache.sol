// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/************
@title IAssetRiskCache interface
@notice Interface for caching asset risks
*/
interface IOracle {
  /***********
    @dev
     */
  function getAssetRisk(address asset) public view returns (int delta, int PNL);
}
