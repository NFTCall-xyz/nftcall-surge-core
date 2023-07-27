// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import {IERC20, IERC20Metadata, ERC20, ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SimpleInitializable} from "../libraries/SimpleInitializable.sol";
import {GENERAL_UNIT} from "../libraries/DataTypes.sol";

import "../interfaces/ILPToken.sol";

contract LPToken is ILPToken, ERC4626, Ownable, SimpleInitializable {
    using Math for uint256;
    using SafeERC20 for IERC20;
    struct UserLockedBalanceData {
        uint256 lockedBalance;
        uint256 releaseTime;
    }
    mapping(address => UserLockedBalanceData) private _lockedBalances;
    address private _vault = address(0);
    uint256 private _maximumVaultBalance = 0;
    uint256 private _minimumAssetToShareRatio = GENERAL_UNIT * 10 / 100; // 10%
    uint256 private _totalLockedBalance = 0;
    uint256 private _totalAssets = 0;
    uint256 public constant MAXIMUM_WITHDRAW_RATIO = GENERAL_UNIT * 50 / 100; // 50%
    uint256 public constant WITHDRAW_FEE_RATIO = GENERAL_UNIT * 3 / 1000; // 0.3%
    uint256 public constant LOCK_PERIOD = 3 days;
    
    constructor(address assetAddress, string memory name, string memory symbol) 
      ERC4626(IERC20(assetAddress)) 
      ERC20(name, symbol)
      Ownable()
    {

    }

    modifier onlyVault() {
        if (_msgSender() != _vault) {
            revert OnlyVault(address(this), _msgSender(), _vault);
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
        if(_lockedBalances[user].releaseTime > 0 && block.timestamp >= _lockedBalances[user].releaseTime){
            return 0;
        }
        return _lockedBalances[user].lockedBalance;
    }

    function balanceOf(address user) public override(ERC20, IERC20) virtual view returns(uint256) {
        if(_lockedBalances[user].releaseTime > 0 && block.timestamp >= _lockedBalances[user].releaseTime){
            return super.balanceOf(user) + _lockedBalances[user].lockedBalance;
        }
        return super.balanceOf(user);
    }

    function releaseTime(address user) public override view returns(uint256) {
        return _lockedBalances[user].releaseTime;
    }

    function totalAssets() public view override returns (uint256) {
        IVault vaultContract = IVault(_vault);
        int256 assets = int256(_totalAssets - vaultContract.unrealizedPremium()) + vaultContract.unrealizedPNL();
        return assets > 0 ? uint256(assets) : 0;
    }

    function increaseTotalAssets(uint256 amount) public override onlyVault {
        _updateTotalAssets(_totalAssets + amount);
    }

    function decreaseTotalAssets(uint256 amount) public override onlyVault {
        _updateTotalAssets(_totalAssets - amount);
    }

    function _updateTotalAssets(uint256 assets) internal {
        _totalAssets = assets;
        emit UpdateTotalAssets(assets);
    }

    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return super.totalSupply() + _totalLockedBalance;
    }


    function maxDeposit(address) public view override returns (uint256) {
        return _maxDeposit();
    }

    function maxMint(address) public view override returns (uint256) {
        return _convertToShares(_maxDeposit(), Math.Rounding.Down);
    }

    function _maxDeposit() internal view returns (uint256) {
        return (_totalAssets < _maximumVaultBalance) ? (_maximumVaultBalance - _totalAssets) : 0;
    }

    function maxWithdraw(address user) public view override returns (uint256) {
        return _maxWithdraw(user);
    }

    function _maxWithdraw(address user) internal view returns (uint256) {
        uint256 userBalance = balanceOf(user);
        if(userBalance == 0) {
            return 0;
        }
        userBalance = _convertToAssets(userBalance, Math.Rounding.Down);
        return Math.min(userBalance, _maxWithdrawBalance());
    }

    function maxRedeem(address user) public view override returns (uint256) {
        return _maxRedeem(user);
    }

    function _maxRedeem(address user) internal view returns (uint256) {
        uint256 userBalance = balanceOf(user);
        if(userBalance == 0) {
            return 0;
        }
        return Math.min(userBalance, _convertToShares(_maxWithdrawBalance(), Math.Rounding.Down));
    }

    function _maxWithdrawBalance() internal view returns (uint256) {
        uint256 _totalLockedAssets = IVault(_vault).totalLockedAssets();
        return (_totalAssets > _totalLockedAssets) ? (_totalAssets - _totalLockedAssets).mulDiv(MAXIMUM_WITHDRAW_RATIO, GENERAL_UNIT, Math.Rounding.Down) : 0;
    }

    function deposit(uint256 assets, address receiver) public override returns(uint256){
        uint256 maximumDepositAssets = maxDeposit(receiver);
        if(assets > maximumDepositAssets){
            revert DepositMoreThanMax(address(this), assets, maximumDepositAssets);
        }
        uint256 shares = previewDeposit(assets);
        if(shares.mulDiv(_minimumAssetToShareRatio, GENERAL_UNIT, Math.Rounding.Up) > assets){
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
        if(shares.mulDiv(_minimumAssetToShareRatio, GENERAL_UNIT, Math.Rounding.Up) > assets){
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
        if(shares.mulDiv(_minimumAssetToShareRatio, GENERAL_UNIT, Math.Rounding.Up) > assets){
            revert InsufficientAssetToShareRatio(address(this), assets, shares, _minimumAssetToShareRatio);
        }
        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns(uint256){
        uint256 maximumWithdrawAssets = _maxWithdraw(owner);
        if(assets == type(uint256).max){
            assets = maximumWithdrawAssets;
        }
        else if(assets > maximumWithdrawAssets){
            revert WithdrawMoreThanMax(address(this), assets, maximumWithdrawAssets);
        }    
        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns(uint256) {
        uint256 maximumRedeemShares = _maxRedeem(owner);
        if(shares == type(uint256).max){
            shares = maximumRedeemShares;
        }
        else if(shares > maximumRedeemShares){
            revert RedeemMoreThanMax(address(this), shares, maximumRedeemShares);
        }
        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function untitledAssets() public view override returns(uint256) {
        return IERC20(asset()).balanceOf(address(this)) - _totalAssets;
    }

    function collectUntitledAssets(address receiver) public onlyVault override returns(uint256) {
        uint256 amount = untitledAssets();
        if(amount == 0){
            revert NoAssetsToCollect(address(this));
        }
        IERC20(asset()).safeTransfer(receiver, amount);
        emit Collect(receiver, amount);
        return amount;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _claim(receiver);
        _totalAssets += assets;
        _lockedBalances[receiver].lockedBalance += shares;
        _totalLockedBalance +=  shares;
        _lockedBalances[receiver].releaseTime = block.timestamp + LOCK_PERIOD;
        // _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
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
        uint256 fee = assets.mulDiv(WITHDRAW_FEE_RATIO, GENERAL_UNIT, Math.Rounding.Up);
        IERC20 erc20Asset = IERC20(asset());
        address reserve = IVault(_vault).reserve();
        erc20Asset.safeTransfer(reserve, fee);
        uint256 feeShares = _convertToShares(fee, Math.Rounding.Up);
        _totalAssets -= assets;
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

    function _claim(address user) internal returns(uint256 shares) {
        if(_lockedBalances[user].releaseTime > 0 && block.timestamp < _lockedBalances[user].releaseTime){
            return 0;
        }
        shares = _lockedBalances[user].lockedBalance;
        if(shares > 0){
            _lockedBalances[user].lockedBalance -= shares;
            _lockedBalances[user].releaseTime = 0;
            _totalLockedBalance -= shares;
            _mint(user, shares);
            emit Claim(user, shares);
        }
    }

     function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0)) { // transfer or burn
            _claim(from);
        }
        else { // mint
            _claim(to);
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}