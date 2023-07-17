// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface ILPToken {
    event UpdateMaximumVaultBalance(uint256 maxVaultBalance);
    event Initialize(address indexed vault, uint256 maxVaultBalance);
    event UpdateMinimumAssetToShareRatio(uint256 ratio);
    event Claim(address indexed user, uint256 amount);
    event Collect(address indexed receiver, uint256 amount);
    event UpdateTotalAssets(uint256 amount);

    function vault() external view returns(address);
    function maximumVaultBalance() external view returns(uint256);
    function setMaximumVaultBalance(uint256 maxVaultBalance) external;
    function lockedBalanceOf(address user) external view returns(uint256);
    function releaseTime(address user) external view returns(uint256);
    function setMinimumAssetToShareRatio(uint256 ratio) external;
    function deposit(uint256 assets, address user, address receiver) external returns(uint256);
    function untitledAssets() external view returns(uint256);
    function collect(address receiver) external returns(uint256);
    function increaseTotalAssets(uint256 amount) external;
    function decreaseTotalAssets(uint256 amount) external;

    error OnlyVault(address thrower, address caller, address vault);
    error ZeroVaultAddress(address thrower);
    error DepositMoreThanMax(address thrower, uint256 assets, uint256 maxDepositableAssets);
    error MintMoreThanMax(address thrower, uint256 shares, uint256 maxMintableShares);
    error WithdrawMoreThanMax(address thrower, uint256 assets, uint256 maxWithdrawableAssets);
    error RedeemMoreThanMax(address thrower, uint256 shares, uint256 maxRedeemableShares);
    error InsufficientAssetToShareRatio(address thrower, uint256 assets, uint256 shares, uint256 minimumRatio);
    error NoAssetsToCollect(address thrower);
}    