// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PERCENTAGE_FACTOR, PercentageMath} from "./libraries/math/PercentageMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOptionToken.sol";
import {IPricer} from "./interfaces/IPricer.sol";

import "./tokens/LPToken.sol";

import "./interfaces/ISurgeUI.sol";

contract SurgeUI {
    using Math for uint256;
    using PercentageMath for uint256;

    uint256 private constant PREMIUM_UPSCALE_RATIO =
        (PERCENTAGE_FACTOR * 150) / 100; // 150%

    function _getNFTCollection(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress
    ) internal view returns (NFTCollection memory) {
        NFTCollection memory collection_;

        IOracle oracleInstance = IOracle(oracleAddress);
        (collection_.price, collection_.vol) = oracleInstance
            .getAssetPriceAndVol(collectionAddress);

        IVault vaultInstance = IVault(vaultAddress);
        collection_.maximumOptionAmount = vaultInstance.maximumOptionAmount(
            collectionAddress,
            OptionType.LONG_CALL
        );
        // collection_.maximumOptionAmount = 0;

        return collection_;
    }

    function getNFTCollections(
        address[] memory collectionAddresses,
        address oracleAddress,
        address vaultAddress
    ) external view returns (NFTCollection[] memory) {
        NFTCollection[] memory collections = new NFTCollection[](
            collectionAddresses.length
        );
        for (uint256 i = 0; i < collectionAddresses.length; i++) {
            collections[i] = _getNFTCollection(
                collectionAddresses[i],
                oracleAddress,
                vaultAddress
            );
        }

        return collections;
    }

    function getNFTCollection(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress
    ) external view returns (NFTCollection memory) {
        return
            _getNFTCollection(collectionAddress, oracleAddress, vaultAddress);
    }

    function _getVault(
        address vaultAddress,
        address lpTokenAddress,
        address wETHAddress,
        address userAddress
    ) internal view returns (Vault memory) {
        Vault memory vault_;

        IVault vaultInstance = IVault(vaultAddress);

        if (userAddress != address(0)) {
            ERC20 wETHInstance = ERC20(wETHAddress);
            LPToken lpTokenInstance = LPToken(lpTokenAddress);

            vault_.lpToken.balance = lpTokenInstance.balanceOf(userAddress);
            vault_.lpToken.wETHBalance = wETHInstance.balanceOf(userAddress);
            vault_.lpToken.lockedBalance = lpTokenInstance.lockedBalanceOf(
                userAddress
            );
            vault_.lpToken.maxWithdraw = lpTokenInstance.maxWithdraw(
                userAddress
            );
            vault_.lpToken.releaseTime = lpTokenInstance.releaseTime(
                userAddress
            );
        }

        vault_.totalAssets = vaultInstance.totalAssets();
        vault_.totalLockedAssets = vaultInstance.totalLockedAssets();
        vault_.unrealizedPNL = vaultInstance.unrealizedPNL();
        vault_.unrealizedPremium = vaultInstance.unrealizedPremium();

        return vault_;
    }

    function getVaultWithUser(
        address vaultAddress,
        address lpTokenAddress,
        address wETHAddress,
        address userAddress
    ) external view returns (Vault memory) {
        return
            _getVault(vaultAddress, lpTokenAddress, wETHAddress, userAddress);
    }

    function getVault(
        address vaultAddress,
        address lpTokenAddress,
        address wETHAddress
    ) external view returns (Vault memory) {
        address userAddress = address(0);
        return
            _getVault(vaultAddress, lpTokenAddress, wETHAddress, userAddress);
    }

    function getPosition(
        address optionTokenAddress,
        uint256 positionId
    ) external view returns (OptionPosition memory) {
        IOptionToken optionTokenInstance = IOptionToken(optionTokenAddress);
        return optionTokenInstance.optionPosition(positionId);
    }

    function getPremium(
        address pricerAddress,
        address collection,
        OptionType optionType,
        Strike memory strike_
    ) external view returns (uint256) {
        IPricer pricer = IPricer(pricerAddress);
        uint256 adjustedVol = pricer.getAdjustedVol(
            collection,
            optionType,
            strike_.strikePrice
        );
        uint256 premium = pricer
            .getPremium(
                optionType,
                strike_.spotPrice,
                strike_.strikePrice,
                adjustedVol,
                strike_.duration
            )
            .percentMul(PREMIUM_UPSCALE_RATIO);

        return premium;
    }
}
