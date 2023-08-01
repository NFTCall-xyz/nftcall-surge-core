// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OptionType} from "./IOptionToken.sol";
import {BlackScholes} from "../libraries/BlackScholes.sol";

interface IPricer {
    function getPremiumDeltaStdVega(OptionType optionType, uint S, uint K, uint vol, uint duration) external view returns (uint premium, int delta, uint vega, uint stdVega);
    function getAdjustedVol(address asset, OptionType ot, uint K, uint lockValue) external view returns (uint adjustedVol);
    function optionPrices(uint S, uint K, uint vol, uint duration) external view returns (uint call, uint put);
    function optionPricesDeltaStdVega(uint S, uint K, uint vol, uint duration) external view returns (BlackScholes.PricesDeltaStdVega memory);
    function optionDelta(uint S, uint K, uint vol, uint druation) external view returns (int callDelta, int putDelta);

    error IllegalStrikePrice(address thrower, uint S, uint K);
}