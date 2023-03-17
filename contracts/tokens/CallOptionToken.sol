// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {OptionBase} from "./OptionBase.sol";

contract CallOptionToken is OptionBase {
    constructor(address collectionAddress, string memory baseURI)
      OptionBase(collectionAddress, "NFTSurge", "Call", "call", "", baseURI)
    {}
}