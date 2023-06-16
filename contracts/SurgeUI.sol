// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";
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

        collection_.openInterest = _getOpenInterest(
            vaultAddress,
            vaultInstance.marketConfiguration(collectionAddress).optionToken
        );

        return collection_;
    }

    function _getOpenInterest(
        address vaultAddress,
        address optionTokenAddress
    ) internal view returns (uint256 totalActiveAmount) {
        totalActiveAmount = 0;

        IVault vaultInstance = IVault(vaultAddress);
        OptionToken optionTokenInstance = OptionToken(optionTokenAddress);
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < optionTokenInstance.totalSupply(); ++i) {
            uint256 tokenId = optionTokenInstance.tokenByIndex(i);
            OptionPosition memory position = optionTokenInstance.optionPosition(
                tokenId
            );
            if (
                position.state == PositionState.ACTIVE &&
                vaultInstance.strike(position.strikeId).expiry > currentTime
            ) {
                totalActiveAmount += position.amount;
            }
        }
        return totalActiveAmount;
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
}
