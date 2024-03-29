// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

struct PremiumVars {
  uint256 entryPrice;
  uint256 strikePrice;
  uint256 duration;
  uint256 vol;
}

interface IPremium {
  function getCallPremium(uint256 entryPrice, uint256 strikePrice, uint256 duration, uint256 vol) external view returns (uint256);
  function getPutPremium(uint256 entryPrice, uint256 strikePrice, uint256 duration, uint256 vol) external view returns (uint256);
  function precision() external pure returns (uint256);
}
