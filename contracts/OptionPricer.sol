//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

// Libraries
import "./synthetix/SignedDecimalMath.sol";
import "./synthetix/DecimalMath.sol";
import "./libraries/BlackScholes.sol";
import "openzeppelin-contracts-4.4.1/utils/math/SafeCast.sol";

// Inherited
import "./synthetix/Owned.sol";
import "./libraries/SimpleInitializable.sol";
import "./libraries/Math.sol";

// Interfaces
import "./RiskCache.sol";
import "./NFTCallOracle.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IAssetRiskCache.sol";


/**
 * @title OptionMarketPricer
 * @author Lyra
 * @dev Logic for working out the price of an option. Includes the IV impact of the trade, the fee components and
 * premium.
 */
contract OptionPricer is Owned, SimpleInitializable {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using BlackScholes for BlackScholes.BlackScholesInputs;


  enum OptionType {
    CALL,
    PUT
  }

  struct PricerParams {
    uint decimals;
    uint skewP1;
    uint skewP2;
    uint deltaP1;
    uint deltaP2;
  }

  AssetRiskCache internal risk;
  NFTCallOracle internal oracle;
  PricerParams private pricerParams;

  /**
   * S is the price of the underlying asset at open time
   * K is the strike price of option
   */
  function getAdjustedVol(address asset, OptionType ot, uint K, uint duration) public view returns (uint adjustedVol) {
    (uint S, uint vol) = IOracle(oracle).getAssetPriceAndVol(asset);
    (int delta, int PNL) = IAssetRiskCache(risk).getAssetRisk(asset);
    uint riskDecimals = IAssetRiskCache(risk).getRiskDecimals();
    // Impact of skew, delta, and PNL
    if (ot == OptionType.CALL) {
      require(K > S, "Illegal strike price for CALL");
      adjustedVol = vol + vol*(K-S)*pricerParams.skewP1/S/pricerParams.decimals + vol*(K-S)*(K-S)*pricerParams.skewP2/S/S/pricerParams.decimals;
      adjustedVol -= adjustedVol * delta * (delta <= 0 ? pricerParams.deltaP1 : pricerParams.deltaP2) / (riskDecimals*pricerParams.decimals);
    } else {
      require(K < S, "Illegal strike price for PUT");
      rK = S * S / K;
      adjustedVol = vol + vol*(rK-S)*pricerParams.skewP1/S/pricerParams.decimals + vol*(rK-S)*(rK-S)*pricerParams.skewP2/S/S/pricerParams.decimals;
      adjustedVol += adjustedVol * delta * (delta >= 0 ? pricerParams.deltaP1 : pricerParams.deltaP2) / (riskDecimals*pricerParams.decimals);
    }
    // Collateral and amount impact

  }

  function getPremium(uint S, uint K, uint vol, uint duration) public view returns (uint premium) {
    premium = 100;
  }

  
}
