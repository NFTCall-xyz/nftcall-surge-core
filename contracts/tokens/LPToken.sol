// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import {IERC20, IERC20Metadata, ERC20, ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILPToken} from "../interfaces/ILPToken.sol";

contract LPToken is ILPToken, ERC4626, Ownable {
    using Math for uint256;
    
    constructor(address assetAddress) 
      ERC4626(IERC20(assetAddress)) ERC20("", "") Ownable()
    {

    }

    function mint(address onBehalfOf, uint256 amount) public override onlyOwner
    {

    }

    function burn(address user, address to, uint256 amount) public override onlyOwner
    {

    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
      return string(abi.encodePacked("NFTSurge " , ERC20(asset()).name(), " Liquidity Provider Token"));
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
      return string(abi.encodePacked("nlp" , ERC20(asset()).symbol()));
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