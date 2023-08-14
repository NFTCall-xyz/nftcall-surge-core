// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct NFTCollection {
    uint256 price;
    uint256 vol;
    uint256 maximumOptionAmount;
}

struct NFTCollectionStaus {
    uint256 price;
    uint256 vol;
    int256 delta;
    int256 unrealizedPNL;
    uint256 openInterest;
    uint256 optionTokenTotalValue;
    uint256 optionTokenTotalLockedValue;
    uint256 collectionWeight;
    uint256 callOptionAmount;
    uint256 putOptionAmount;
}

struct VaultLPToken {
    uint256 wETHBalance;
    uint256 wETHAllowance;
    uint256 balance;
    uint256 allowance;
    uint256 lockedBalance;
    uint256 maxWithdraw;
    uint256 maxRedeem;
    uint256 releaseTime;
}

struct Vault {
    VaultLPToken lpToken;
    uint256 ncETHPrice;
    uint256 wETHAllowance;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 executionFee;
    uint256 reserveRatio;
    uint256 feeRatio;
    uint256 profitFeeRatio;
    uint256 timeWindowForActivation;
    uint256 maximumLockRatio;
    uint256 maximumCallStrikePriceRatio;
    uint256 maximumPutStrikePriceRatio;
    uint256 minimumCallStrikePriceRatio;
    uint256 minimumPutStrikePriceRatio;
    uint256 maximumDuration;
    uint256 minimumDuration;
    uint256 timeScale;
    uint256 totalLockedAssets;
    int256 unrealizedPNL;
    uint256 unrealizedPremium;
}

struct Analytics {
    uint256 TVL;
    uint256 ncETHPrice;
}
