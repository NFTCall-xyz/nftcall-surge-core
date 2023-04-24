// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface ILPToken {
    event UpdateMaximumVaultBalance(uint256 maxVaultBalance);
    event Initialize(address indexed vault, uint256 maxVaultBalance);
    event UpdateMinimumAssetToShareRatio(uint256 ratio);
    event UnlockBalance(address indexed user, uint256 amount);
    function vault() external view returns(address);
    function maximumVaultBalance() external view returns(uint256);
    function setMaximumVaultBalance(uint256 maxVaultBalance) external;
    function lockedBalanceOf(address user) external view returns(uint256);
    function unlockBalance(address user, uint256 amount) external;
    function setMinimumAssetToShareRatio(uint256 ratio) external;
    function deposit(uint256 assets, address user, address receiver) external returns(uint256);

    error OnlyVault(address thrower, address caller, address vault);
    error ZeroVaultAddress(address thrower);
    error DepositMoreThanMax(address thrower, uint256 assets, uint256 maxDepositableAssets);
    error MintMoreThanMax(address thrower, uint256 shares, uint256 maxMintableShares);
    error WithdrawMoreThanMax(address thrower, uint256 assets, uint256 maxWithdrawableAssets);
    error RedeemMoreThanMax(address thrower, uint256 shares, uint256 maxRedeemableShares);
    error InsufficientAssetToShareRatio(address thrower, uint256 assets, uint256 shares, uint256 minimumRatio);
}    