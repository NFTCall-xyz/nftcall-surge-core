// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";

import "./interfaces/ISurgeUI.sol";

contract SurgeUI {
    function _getCollection(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress
    ) internal view returns (Collection memory) {
        Collection memory collection_;

        IOracle oracleInstance = IOracle(oracleAddress);
        (collection_.price, collection_.vol) = oracleInstance
            .getAssetPriceAndVol(collectionAddress);

        // IVault vaultInstance = IVault(vaultAddress);
        // collection_.maximumOptionAmount = vaultInstance.maximumOptionAmount(
        //     collectionAddress,
        //     OptionType.LONG_CALL
        // );
        collection_.maximumOptionAmount = 0;

        return collection_;
    }

    function getCollections(
        address[] memory collectionAddresses,
        address oracleAddress,
        address vaultAddress
    ) external view returns (Collection[] memory) {
        Collection[] memory collections = new Collection[](
            collectionAddresses.length
        );
        for (uint256 i = 0; i < collectionAddresses.length; i++) {
            collections[i] = _getCollection(
                collectionAddresses[i],
                oracleAddress,
                vaultAddress
            );
        }

        return collections;
    }

    function getCollection(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress
    ) external view returns (Collection memory) {
        return _getCollection(collectionAddress, oracleAddress, vaultAddress);
    }
}
