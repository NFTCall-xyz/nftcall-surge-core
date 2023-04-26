//SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

// Libraries
import {SignedDecimalMath} from "./synthetix/SignedDecimalMath.sol";
import {DecimalMath} from "./synthetix/DecimalMath.sol";
import {BlackScholes} from "./libraries/BlackScholes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Inherited
import "./libraries/SimpleInitializable.sol";
import "./libraries/Math.sol";

// Interfaces
import "./AssetRiskCache.sol";
import "./NFTCallOracle.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IAssetRiskCache.sol";
import {OptionType} from "./interfaces/IOptionToken.sol";
import {GENERAL_DECIMALS, GENERAL_UNIT } from "./libraries/DataTypes.sol";
import { PERCENTAGE_FACTOR } from "./libraries/math/PercentageMath.sol";


import "./interfaces/IPricer.sol";

import "hardhat/console.sol";


/**
 * @title OptionMarketPricer
 * @author Lyra
 * @dev Logic for working out the price of an option. Includes the IV impact of the trade, the fee components and
 * premium.
 */
contract OptionPricer is IPricer, Ownable, SimpleInitializable {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using BlackScholes for BlackScholes.BlackScholesInputs;

  /**
   * skewP1 & skewP2 are used for skew adjustment. i.e., skewP1 = 1000, which is 0.1; skewP2 = 2000, which is actually 0.2
   * deltaP1 & deltaP2 are used for delta adjustment. i.e., deltaP1 = 5000(0.5), deltaP2 = 2000(0.2)
   */
  struct PricerParams {
    uint skewP1;
    uint skewP2;
    uint deltaP1;
    uint deltaP2;
  }

  AssetRiskCache internal risk;
  NFTCallOracle internal oracle;
  PricerParams private pricerParams;
  // riskFreeRate is ETH POS interest rate, now annually 4.8%.
  int private riskFreeRate = int(PERCENTAGE_FACTOR * 48 / 1000);

  function initialize(address riskCache_, address oracle_) public onlyOwner initializer {
    risk = AssetRiskCache(riskCache_);
    oracle = NFTCallOracle(oracle_);
    pricerParams.skewP1 = GENERAL_UNIT * 10 / 100; // 0.1
    pricerParams.skewP2 = GENERAL_UNIT * 20 / 100; // 0.2
    pricerParams.deltaP1 = GENERAL_UNIT * 50 / 100; // 0.5
    pricerParams.deltaP2 = GENERAL_UNIT * 20 / 100; // 0.2
  }

  /**
   * S is the price of the underlying asset at open time
   * K is the strike price of option
   */
  function getAdjustedVol(address asset, OptionType ot, uint K) public view override returns (uint) {
    (uint S, uint vol) = IOracle(oracle).getAssetPriceAndVol(asset);
    (int delta, ) = IAssetRiskCache(risk).getAssetRisk(asset);
    // Impact of skew, delta, and unrealized PNL
    int adjustedVol = int(vol);
    if (ot == OptionType.LONG_CALL) {
      require(K > S, "Illegal strike price for CALL");
      adjustedVol += int(vol*(K-S)*pricerParams.skewP1/S/(GENERAL_UNIT) + vol*(K-S)*(K-S)*pricerParams.skewP2/S/S/(GENERAL_UNIT));
      adjustedVol -= adjustedVol * delta * int(delta <= 0 ? pricerParams.deltaP1 : pricerParams.deltaP2) / int(GENERAL_UNIT**2);
    } else {
      require(K < S, "Illegal strike price for PUT");
      uint rK = S * S / K;
      adjustedVol += int(vol*(rK-S)*pricerParams.skewP1/S/(GENERAL_UNIT) + vol*(rK-S)*(rK-S)*pricerParams.skewP2/S/S/(GENERAL_UNIT));
      adjustedVol += adjustedVol * delta * int(delta >= 0 ? pricerParams.deltaP1 : pricerParams.deltaP2) / int(GENERAL_UNIT**2);
    }
    // Collateral and amount impact
    return uint(adjustedVol);
  }

  function getPremium(OptionType ot, uint S, uint K, uint vol, uint duration) public view override returns (uint) {
    (uint call, uint put) = optionPrices(S, K, vol, duration);
    console.log("got price: %s, %s", call, put);
    if (ot == OptionType.LONG_CALL)
      return call;
    else if (ot == OptionType.LONG_PUT)
      return put;
    else
      return 0;
  }

  function optionPrices(uint S, uint K, uint vol, uint duration) public view returns (uint call, uint put) {
    uint decimalsDiff = 10 ** (DecimalMath.decimals-GENERAL_DECIMALS);
    BlackScholes.BlackScholesInputs memory bsInput = BlackScholes.BlackScholesInputs(
      duration,
      vol,
      S,
      K,
      riskFreeRate * int(decimalsDiff)
    );
    console.log('duration: %s, vol: %s,  riskFreeRate: %s', duration, vol, uint256(bsInput.rateDecimal));
    console.log('strike price: %s, spot price: %s', K, S);
    (call, put) = BlackScholes.optionPrices(bsInput);
    call /= decimalsDiff;
    put /= decimalsDiff;
  }

  function updatePricerParams(uint skewP1, uint skewP2, uint deltaP1, uint deltaP2) external onlyOwner {
    pricerParams = PricerParams(skewP1, skewP2, deltaP1, deltaP2);
  }
}
