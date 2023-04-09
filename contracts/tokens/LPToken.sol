// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import {IERC20, IERC20Metadata, ERC20, ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILPToken} from "../interfaces/ILPToken.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SimpleInitializable} from "../libraries/SimpleInitializable.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";


contract LPToken is ILPToken, ERC4626, Ownable, SimpleInitializable {
    using Math for uint256;
    using PercentageMath for uint256;
    mapping(address => uint256) private _lockedBalances;
    address private _vault = address(0);
    uint256 private _maximumVaultBalance = 0;
    uint256 private _minimumAssetToShareRatio = 1000; // 10%
    uint256 private constant MAXIMUM_WITHDRAW_RATIO = 5000; // 50%
    
    constructor(address assetAddress) 
      ERC4626(IERC20(assetAddress)) 
      ERC20(string(abi.encodePacked("NFTSurge " , ERC20(asset()).name(), " Liquidity Provider Token")), 
            string(abi.encodePacked("nlp" , ERC20(asset()).symbol()))) 
      Ownable()
    {

    }

    modifier onlyVault() {
    if (msg.sender != _vault) {
      revert OnlyVault(address(this), msg.sender, _vault);
    }
    _;
  }

    function initialize(address vaultAddress, uint256 maxVaultBalance) public onlyOwner initializer {
        if(vaultAddress == address(0)){
            revert ZeroVaultAddress(address(this));
        }
        _vault = vaultAddress;
        _maximumVaultBalance = maxVaultBalance;
        emit Initialize(vaultAddress, maxVaultBalance);
    }

    function vault() public view override returns(address) {
        return _vault;
    }

    function maximumVaultBalance() public view override returns(uint256) {
        return _maximumVaultBalance;
    }

    function setMaximumVaultBalance(uint256 maxVaultBalance) public override onlyOwner {
        _maximumVaultBalance = maxVaultBalance;
        emit UpdateMaximumVaultBalance(maxVaultBalance);
    }

    function setMinimumAssetToShareRatio(uint256 ratio) public override onlyOwner {
        _minimumAssetToShareRatio = ratio;
        emit UpdateMinimumAssetToShareRatio(ratio);
    }

    function lockedBalanceOf(address user) public override view returns(uint256) {
        return _lockedBalances[user];
    }

    function unlockBalance(address user, uint256 amount) public override onlyVault {
        if(_lockedBalances[user] == 0) return;
        _lockedBalances[user] -= amount;
    }

    function totalAssets() public view override returns (uint256) {
        IVault vaultContract = IVault(_vault);
        int256 assets = int256(ERC4626.totalAssets() - vaultContract.unrealizedPremium()) + vaultContract.unrealizedPNL();
        return assets > 0 ? uint256(assets) : 0;
    }


    function maxDeposit(address) public view override returns (uint256) {
        return _maxDeposit();
    }

    function maxMint(address) public view override returns (uint256) {
        return _convertToShares(_maxDeposit(), Math.Rounding.Down);
    }

    function _maxDeposit() internal view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return (_totalAssets < _maximumVaultBalance) ? (_maximumVaultBalance - _totalAssets) : 0;
    }

    function maxWithdraw(address user) public view override returns (uint256) {
        return _maxWithdraw(user);
    }

    function _maxWithdraw(address user) internal view returns (uint256) {
        uint256 userBalance = balanceOf(user) - lockedBalanceOf(user);
        if(userBalance == 0) {
            return 0;
        }
        userBalance = _convertToAssets(userBalance, Math.Rounding.Down);
        return Math.min(userBalance, _maxWithdrawBalance());
    }

    function _maxRedeem(address user) internal view returns (uint256) {
        uint256 userBalance = balanceOf(user) - lockedBalanceOf(user);
        if(userBalance == 0) {
            return 0;
        }
        return Math.min(userBalance, _convertToShares(_maxWithdrawBalance(), Math.Rounding.Down));
    }

    function _maxWithdrawBalance() internal view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalLockedAssets = IVault(_vault).totalLockedAssets();
        return (_totalAssets > _totalLockedAssets) ? (_totalAssets - _totalLockedAssets).percentMul(MAXIMUM_WITHDRAW_RATIO) : 0;
    }

    function deposit(uint256 assets, address receiver) public override returns(uint256){
        uint256 maximumDepositAssets = maxDeposit(receiver);
        if(assets > maximumDepositAssets){
            revert DepositMoreThanMax(address(this), assets, maximumDepositAssets);
        }
        uint256 shares = previewDeposit(assets);
        if(shares.percentMul(_minimumAssetToShareRatio) > assets){
            revert InsufficientAssetToShareRatio(address(this), assets, shares, _minimumAssetToShareRatio);
        }
        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) public override onlyVault returns(uint256) {
        uint256 maximumMintShares = maxMint(receiver);
        if(shares > maximumMintShares){
            revert MintMoreThanMax(address(this), shares, maximumMintShares);
        }
        uint256 assets = previewMint(shares);
        if(shares.percentMul(_minimumAssetToShareRatio) > assets){
            revert InsufficientAssetToShareRatio(address(this), assets, shares, _minimumAssetToShareRatio);
        }
        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 shares, address receiver, address owner) public override returns(uint256){
        uint256 maximumWithdrawShares = maxWithdraw(owner);
        if(shares > maximumWithdrawShares){
            revert WithdrawMoreThanMax(address(this), shares, maximumWithdrawShares);
        }
        uint256 assets = previewWithdraw(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns(uint256) {
        uint256 maximumRedeemShares = _maxRedeem(owner);
        if(shares > maximumRedeemShares){
            revert RedeemMoreThanMax(address(this), shares, maximumRedeemShares);
        }
        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, rounding)
                : assets.mulDiv(supply, totalAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToAssets} when overriding it.
     */
    function _initialConvertToShares(
        uint256 assets,
        Math.Rounding /*rounding*/
    ) internal view override returns (uint256 shares) {
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0) ? _initialConvertToAssets(shares, rounding) : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToShares} when overriding it.
     */
    function _initialConvertToAssets(
        uint256 shares,
        Math.Rounding /*rounding*/
    ) internal view override returns (uint256 assets) {
        return shares;
    }
}