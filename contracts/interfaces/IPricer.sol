// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OptionType} from "./IOptionToken.sol";

interface IPricer {
    function getAdjustedVol(address asset, OptionType ot, uint K) external view returns (uint adjustedVol);
    function getPremium(OptionType optionType, uint S, uint K, uint vol, uint duration) external view returns (uint premium);
    function optionPrices(uint S, uint K, uint vol, uint duration) external view returns (uint call, uint put);
    function delta(uint S, uint K, uint vol, uint druation) external view returns (int callDelta, int putDelta);

    error IllegalStrikePrice(address thrower, uint S, uint K);
}