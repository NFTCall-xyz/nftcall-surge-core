// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import {IERC20, IERC20Metadata, ERC20, ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SimpleInitializable} from "../libraries/SimpleInitializable.sol";
import {PERCENTAGE_FACTOR, PercentageMath} from "../libraries/math/PercentageMath.sol";

import "../interfaces/ILPToken.sol";

contract LPToken is ILPToken, ERC4626, Ownable, SimpleInitializable {
    using Math for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    mapping(address => uint256) private _lockedBalances;
    address private _vault = address(0);
    uint256 private _maximumVaultBalance = 0;
    uint256 private _minimumAssetToShareRatio = PERCENTAGE_FACTOR * 10 / 100; // 10%
    uint256 public constant MAXIMUM_WITHDRAW_RATIO = PERCENTAGE_FACTOR * 50 / 100; // 50%
    uint256 public constant WITHDRAW_FEE_RATIO = PERCENTAGE_FACTOR * 3 / 1000; // 0.3%
    
    constructor(address assetAddress) 
      ERC4626(IERC20(assetAddress)) 
      ERC20(string(abi.encodePacked("NFTSurge " , IERC20Metadata(assetAddress).name(), " Liquidity Provider Token")), 
            string(abi.encodePacked("nlp" , IERC20Metadata(assetAddress).symbol()))) 
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
        IERC20(asset()).safeApprove(vaultAddress, type(uint256).max);
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
        emit UnlockBalance(user, amount);
    }

    function totalAssets() public view override returns (uint256) {
        IVault vaultContract = IVault(_vault);
        int256 assets = int256(super.totalAssets() - vaultContract.unrealizedPremium()) + vaultContract.unrealizedPNL();
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

    function deposit(uint256 assets, address user, address receiver) public override onlyVault returns(uint256){
        uint256 maximumDepositAssets = maxDeposit(receiver);
        if(assets > maximumDepositAssets){
            revert DepositMoreThanMax(address(this), assets, maximumDepositAssets);
        }
        uint256 shares = previewDeposit(assets);
        if(shares.percentMul(_minimumAssetToShareRatio) > assets){
            revert InsufficientAssetToShareRatio(address(this), assets, shares, _minimumAssetToShareRatio);
        }
        _deposit(user, receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) public override returns(uint256) {
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

    function withdraw(uint256 assets, address receiver, address owner) public override returns(uint256){
        uint256 maximumWithdrawShares = maxWithdraw(owner);
        uint256 shares = previewWithdraw(assets);
        if(shares > maximumWithdrawShares){
            revert WithdrawMoreThanMax(address(this), shares, maximumWithdrawShares);
        }
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

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        uint256 fee = assets.percentMul(WITHDRAW_FEE_RATIO);
        IERC20 erc20Asset = IERC20(asset());
        address reserve = IVault(_vault).reserve();
        erc20Asset.safeTransfer(reserve, fee);
        uint256 feeShares = _convertToShares(fee, Math.Rounding.Up);
        erc20Asset.safeTransfer(receiver, (assets - fee));
        emit Withdraw(caller, reserve, owner, fee, feeShares);
        emit Withdraw(caller, receiver, owner, assets - fee, shares - feeShares);
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
    ) internal pure override returns (uint256 shares) {
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
    ) internal pure override returns (uint256 assets) {
        return shares;
    }
}