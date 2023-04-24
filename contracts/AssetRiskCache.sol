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
contract AssetRiskCache is IAssetRiskCache, Ownable, SimpleInitializable, ReentrancyGuard {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using BlackScholes for BlackScholes.BlackScholesInputs;

  struct AssetRisk {
    // The risks is to asset, not to buyers/traders
    int delta;
    int unrealizedPNL;
  }

  // L1 address of asset => its AssetRisk
  mapping(address => AssetRisk) internal assetRisks;
  
  function getAssetRisk(address asset) public view returns (int delta, int PNL) {
    return (assetRisks[asset].delta, assetRisks[asset].unrealizedPNL);
  }

  function updateAssetRisk(address asset, int delta, int PNL) external onlyOwner {
    AssetRisk storage ar = assetRisks[asset];
    ar.delta = delta;
    ar.unrealizedPNL = PNL;
  }
}
