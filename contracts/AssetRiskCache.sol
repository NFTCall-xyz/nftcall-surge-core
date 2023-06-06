//SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

// Libraries
import {SignedDecimalMath} from "./synthetix/SignedDecimalMath.sol";
import {DecimalMath} from "./synthetix/DecimalMath.sol";
import {BlackScholes} from "./libraries/BlackScholes.sol";

// Inherited
import {SimpleInitializable} from "./libraries/SimpleInitializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Interfaces
import {IAssetRiskCache} from "./interfaces/IAssetRiskCache.sol";

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
