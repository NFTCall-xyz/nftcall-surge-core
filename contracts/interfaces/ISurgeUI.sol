// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct NFTCollection {
    uint256 price;
    uint256 vol;
    uint256 maximumOptionAmount;
    uint256 openInterest;
}

struct VaultLPToken {
    uint256 wETHBalance;
    uint256 wETHAllowance;
    uint256 balance;
    uint256 lockedBalance;
    uint256 maxWithdraw;
    uint256 releaseTime;
}

struct Vault {
    VaultLPToken lpToken;
    uint256 ncETHPrice;
    uint256 wETHAllowance;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 executionFee;
    uint256 totalLockedAssets;
    int256 unrealizedPNL;
    uint256 unrealizedPremium;
}

struct Analytics {
    uint256 TVL;
    uint256 ncETHPrice;
}
