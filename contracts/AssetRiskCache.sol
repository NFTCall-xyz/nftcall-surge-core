//SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

// Libraries
import "./synthetix/DecimalMath.sol";
import "./synthetix/SignedDecimalMath.sol";
import "./libraries/BlackScholes.sol";
import "./libraries/Math.sol";

// Inherited
import "./libraries/SimpleInitializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Interfaces
// import "./BaseExchangeAdapter.sol";
import "./OptionPricer.sol";

/**
 * @title RiskCache
 * @author NFTCall
 * @dev Update Delta and PNL for every collection
 */
contract AssetRiskCache is Ownable, SimpleInitializable, ReentrancyGuard {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using BlackScholes for BlackScholes.BlackScholesInputs;

  struct AssetRisk {
    // The risks is to asset, not to buyers/traders
    int delta;
    int PNL;
  }

  // Need a def of decimals for all contracts?
  uint constant public riskDecimals = 1e4;
  // L1 address of asset => its AssetRisk
  mapping(address => AssetRisk) internal assetRisks;
  

  function getAssetRisk(address asset) public view returns (int delta, int PNL) {
    return (assetRisks[asset].delta, assetRisks[asset].PNL);
  }

  function getRiskDecimals() public pure returns (uint) {
    return riskDecimals;
  }

  /*function updateAssetRisk(address asset, int delta, int PNL) external onlyUpdater {
    AssetRisk storage ar = assetRisks[asset];
    ar = AssetRisk(delta, PNL);
  }*/



}
