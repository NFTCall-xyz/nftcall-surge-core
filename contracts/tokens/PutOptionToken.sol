// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {OptionType, OptionBase} from "./OptionBase.sol";

contract PutOptionToken is OptionBase {
    constructor(address collectionAddress, string memory assetName, string memory assetSymbol, string memory baseURI)
      OptionBase(collectionAddress,
        string(abi.encodePacked("NFTSurge ", assetName, " Put")),
        string(abi.encodePacked("put", assetSymbol)),
        baseURI)
    {}

    function _optionType() internal pure override returns(OptionType) {
        return OptionType.LONG_PUT;
    }
}