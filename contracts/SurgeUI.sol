// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/libraries/DataTypes.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IAssetRiskCache.sol";
import {IPricer} from "./interfaces/IPricer.sol";

import "./tokens/LPToken.sol";
import "./tokens/OptionToken.sol";

import "./interfaces/ISurgeUI.sol";

contract SurgeUI {
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

    function _getNFTCollectionStaus(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress,
        address riskCacheAddress
    ) internal view returns (NFTCollectionStaus memory) {
        NFTCollectionStaus memory collectionStatus_;

        IOracle oracleInstance = IOracle(oracleAddress);
        (collectionStatus_.price, collectionStatus_.vol) = oracleInstance
            .getAssetPriceAndVol(collectionAddress);

        IVault vaultInstance = IVault(vaultAddress);

        IVault.CollectionConfiguration
            memory collectionConfiguration_ = vaultInstance.marketConfiguration(
                collectionAddress
            );

        OptionToken optionTokenInstance = OptionToken(
            collectionConfiguration_.optionToken
        );

        collectionStatus_.openInterest = optionTokenInstance.totalAmount();
        collectionStatus_.callOptionAmount = optionTokenInstance.totalAmount(
            OptionType.LONG_CALL
        );
        collectionStatus_.putOptionAmount = optionTokenInstance.totalAmount(
            OptionType.LONG_PUT
        );
        collectionStatus_.optionTokenTotalValue =
            optionTokenInstance.totalValue(OptionType.LONG_CALL) +
            optionTokenInstance.totalValue(OptionType.LONG_PUT);
        collectionStatus_.collectionWeight = collectionConfiguration_.weight;

        IAssetRiskCache riskCacheInstance = IAssetRiskCache(riskCacheAddress);
        (
            collectionStatus_.delta,
            collectionStatus_.unrealizedPNL
        ) = riskCacheInstance.getAssetRisk(collectionAddress);

        return collectionStatus_;
    }

    function getNFTCollectionsStaus(
        address[] memory collectionAddresses,
        address oracleAddress,
        address vaultAddress,
        address riskCacheAddress
    ) external view returns (NFTCollectionStaus[] memory) {
        NFTCollectionStaus[] memory collectionsStaus = new NFTCollectionStaus[](
            collectionAddresses.length
        );
        for (uint256 i = 0; i < collectionAddresses.length; i++) {
            collectionsStaus[i] = _getNFTCollectionStaus(
                collectionAddresses[i],
                oracleAddress,
                vaultAddress,
                riskCacheAddress
            );
        }

        return collectionsStaus;
    }

    function getNFTCollectionStaus(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress,
        address riskCacheAddress
    ) external view returns (NFTCollectionStaus memory) {
        return
            _getNFTCollectionStaus(
                collectionAddress,
                oracleAddress,
                vaultAddress,
                riskCacheAddress
            );
    }

    function _getVault(
        address vaultAddress,
        address lpTokenAddress,
        address wETHAddress,
        address userAddress
    ) internal view returns (Vault memory) {
        Vault memory vault_;

        IVault vaultInstance = IVault(vaultAddress);
        LPToken lpTokenInstance = LPToken(lpTokenAddress);

        if (userAddress != address(0)) {
            ERC20 wETHInstance = ERC20(wETHAddress);

            vault_.lpToken.balance = lpTokenInstance.balanceOf(userAddress);
            vault_.lpToken.allowance = lpTokenInstance.allowance(
                userAddress,
                vaultAddress
            );
            vault_.lpToken.wETHBalance = wETHInstance.balanceOf(userAddress);
            vault_.lpToken.wETHAllowance = wETHInstance.allowance(
                userAddress,
                lpTokenAddress
            );
            vault_.wETHAllowance = wETHInstance.allowance(
                userAddress,
                vaultAddress
            );
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
        vault_.ncETHPrice = lpTokenInstance.convertToAssets(UNIT);
        vault_.totalSupply = lpTokenInstance.totalSupply();
        vault_.executionFee = vaultInstance.KEEPER_FEE();
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
        OptionToken optionTokenInstance = OptionToken(optionTokenAddress);
        return optionTokenInstance.optionPosition(positionId);
    }

    function getAnalytics(
        address vaultAddress,
        address lpTokenAddress
    ) external view returns (Analytics memory) {
        Analytics memory analytics_;

        IVault vaultInstance = IVault(vaultAddress);
        analytics_.TVL = vaultInstance.totalAssets();

        LPToken lpTokenInstance = LPToken(lpTokenAddress);
        analytics_.ncETHPrice = lpTokenInstance.convertToAssets(UNIT);

        return analytics_;
    }
}
