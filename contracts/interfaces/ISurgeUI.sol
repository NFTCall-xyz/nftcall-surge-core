// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct NFTCollection {
    uint256 price;
    uint256 vol;
    uint256 maximumOptionAmount;
}

struct VaultLPToken {
    uint256 wETHBalance;
    uint256 balance;
    uint256 lockedBalance;
    uint256 maxWithdraw;
    uint256 releaseTime;
}

struct Vault {
    VaultLPToken lpToken;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 totalLockedAssets;
    int256 unrealizedPNL;
    uint256 unrealizedPremium;
}
