//SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

// Libraries
import {SignedDecimalMath} from "./synthetix/SignedDecimalMath.sol";
import {DecimalMath} from "./synthetix/DecimalMath.sol";
import {BlackScholes} from "./libraries/BlackScholes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Inherited
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SimpleInitializable} from "./libraries/SimpleInitializable.sol";
import {IPricer} from "./interfaces/IPricer.sol";

// Interfaces
import {IVault} from "./interfaces/IVault.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IAssetRiskCache} from "./interfaces/IAssetRiskCache.sol";

import {Vault} from "./vault/Vault.sol";
import {AssetRiskCache} from "./AssetRiskCache.sol";
import {NFTCallOracle} from "./NFTCallOracle.sol";
import {OptionType, IOptionToken} from "./interfaces/IOptionToken.sol";
import {GENERAL_DECIMALS, GENERAL_UNIT, UNIT } from "./libraries/DataTypes.sol";

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

  uint256 private constant HALF_PERCENT = GENERAL_UNIT / 2;

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

  Vault internal vault;
  AssetRiskCache internal risk;
  NFTCallOracle internal oracle;
  PricerParams private pricerParams;
  // riskFreeRate is ETH POS interest rate, now annually 4.8%.
  int private riskFreeRate = int(GENERAL_UNIT * 48 / 1000);

  function initialize(address vault_, address riskCache_, address oracle_) public onlyOwner initializer {
    vault = Vault(vault_);
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
  function getAdjustedVol(address collection, OptionType ot, uint K, uint lockValue) public view override returns (uint) {
    (uint S, uint vol) = IOracle(oracle).getAssetPriceAndVol(collection);
    (int delta_, ) = IAssetRiskCache(risk).getAssetRisk(collection);
    uint vaultTotalAssets = IVault(vault).totalAssets();
    IVault.CollectionConfiguration memory collectionConfig = IVault(vault).marketConfiguration(collection);
    uint collectionLockedValue = IOptionToken(collectionConfig.optionToken).totalValue();
    // Impact of skew, delta, and unrealized PNL
    int adjustedVol = int(vol);
    if (ot == OptionType.LONG_CALL) {
      if (K <= S) {
        revert IllegalStrikePrice(_msgSender(), S, K);
      }
      adjustedVol += int(vol*(K-S)*pricerParams.skewP1/S/(GENERAL_UNIT) + vol*(K-S)*(K-S)*pricerParams.skewP2/S/S/(GENERAL_UNIT));
      adjustedVol -= adjustedVol * delta_ * int(delta_ <= 0 ? pricerParams.deltaP1 : pricerParams.deltaP2) * int(collectionLockedValue + lockValue) / int(UNIT) / int(vaultTotalAssets) / int(uint(collectionConfig.weight));
    } else {
      if (K >= S) {
        revert IllegalStrikePrice(_msgSender(), S, K);
      }
      uint rK = S * S / K;
      adjustedVol += int(vol*(rK-S)*pricerParams.skewP1/S/(GENERAL_UNIT) + vol*(rK-S)*(rK-S)*pricerParams.skewP2/S/S/(GENERAL_UNIT));
      adjustedVol += adjustedVol * delta_ * int(delta_ >= 0 ? pricerParams.deltaP1 : pricerParams.deltaP2) * int(collectionLockedValue + lockValue) / int(UNIT) / int(vaultTotalAssets) / int(uint(collectionConfig.weight));
    }
    // Impact of collateralization ratio
    uint cr = IVault(vault).totalLockedAssets() * GENERAL_UNIT / vaultTotalAssets;
    if (cr > HALF_PERCENT) {
      adjustedVol += adjustedVol * int(cr - HALF_PERCENT) / int(GENERAL_UNIT);
    }
    return uint(adjustedVol);
  }

  function getPremiumDeltaStdVega(OptionType ot, uint S, uint K, uint vol, uint duration) public view override returns (uint, int, uint, uint) {
    BlackScholes.PricesDeltaStdVega memory pricesDeltaStdVega = optionPricesDeltaStdVega(S, K, vol, duration);
    if (ot == OptionType.LONG_CALL)
      return (pricesDeltaStdVega.callPrice, pricesDeltaStdVega.callDelta, pricesDeltaStdVega.vega, pricesDeltaStdVega.stdVega);
    else if (ot == OptionType.LONG_PUT)
      return (pricesDeltaStdVega.putPrice, pricesDeltaStdVega.putDelta, pricesDeltaStdVega.vega, pricesDeltaStdVega.stdVega);
    else
      return (0, 0, 0, 0);
  }

  function optionPrices(uint S, uint K, uint vol, uint duration) public view override returns (uint call, uint put) {
    uint decimalsDiff = 10 ** (DecimalMath.decimals-GENERAL_DECIMALS);
    BlackScholes.BlackScholesInputs memory bsInput = BlackScholes.BlackScholesInputs(
      duration,
      vol,
      S,
      K,
      riskFreeRate * int(decimalsDiff)
    );
    (call, put) = BlackScholes.optionPrices(bsInput);
  }

  function optionPricesDeltaStdVega(uint S, uint K, uint vol, uint duration) public view override returns (BlackScholes.PricesDeltaStdVega memory pricesDeltaStdVega) {
    uint decimalsDiff = 10 ** (DecimalMath.decimals-GENERAL_DECIMALS);
    BlackScholes.BlackScholesInputs memory bsInput = BlackScholes.BlackScholesInputs(
      duration,
      vol,
      S,
      K,
      riskFreeRate * int(decimalsDiff)
    );
    pricesDeltaStdVega = BlackScholes.pricesDeltaStdVega(bsInput);
  }

  function delta(uint S, uint K, uint vol, uint duration) public view override returns (int callDelta, int putDelta) {
    uint decimalsDiff = 10 ** (DecimalMath.decimals-GENERAL_DECIMALS);
    BlackScholes.BlackScholesInputs memory bsInput = BlackScholes.BlackScholesInputs(
      duration,
      vol,
      S,
      K,
      riskFreeRate * int(decimalsDiff)
    );
    (callDelta, putDelta) = BlackScholes.delta(bsInput);
    return (callDelta, putDelta);
  }

  function updatePricerParams(uint skewP1, uint skewP2, uint deltaP1, uint deltaP2) external onlyOwner {
    pricerParams = PricerParams(skewP1, skewP2, deltaP1, deltaP2);
  }
}
