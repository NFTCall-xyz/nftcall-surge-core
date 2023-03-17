// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

struct PremiumVars {
  uint8 strikePriceGapIndex;
  uint8 durationIndex;
  uint16 vaultUtilization;
  uint16 collectionUtilization;
  uint256 price;
  uint256 vol;
  uint256 amount;
  uint256 collectionDelta;
  int256 collectionPNL;
}

interface IPremium {
  function getCallPremium(PremiumVars memory vars) external view returns (uint256);
  function getPutPremium(PremiumVars memory vars) external view returns (uint256);
  function precision() external pure returns (uint256);
}
