//SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

// Libraries
import {SignedDecimalMath} from "./synthetix/SignedDecimalMath.sol";
import {DecimalMath} from "./synthetix/DecimalMath.sol";
import {BlackSholes} from "./libraries/BlackScholes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Inherited
import "./synthetix/Owned.sol";
import "./libraries/SimpleInitializable.sol";
import "./libraries/Math.sol";

// Interfaces
import "./AssetRiskCache.sol";
import "./NFTCallOracle.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IAssetRiskCache.sol";
import {OptionType} from "./interfaces/IOptionBase.sol";


/**
 * @title OptionMarketPricer
 * @author Lyra
 * @dev Logic for working out the price of an option. Includes the IV impact of the trade, the fee components and
 * premium.
 */
contract OptionPricer is Ownable, SimpleInitializable {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using BlackScholes for BlackScholes.BlackScholesInputs;


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
    if (ot == OptionType.LONG_CALL) {
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

  function getPremium(address asset, uint S, uint K, uint vol, uint duration) public view returns (uint premium) {
    premium = 100;
  }

  
}
