// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OptionType} from "./IOptionToken.sol";

interface IPricer {
    function getAdjustedVol(address asset, OptionType ot, uint K, uint duration) external view returns (uint adjustedVol);
    function getPremium(address asset, uint S, uint K, uint vol, uint duration) external view returns (uint premium);
}