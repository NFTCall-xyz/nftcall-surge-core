// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";

contract SurgeUI {
    function getCollections(
        address[] memory collectionAddresses,
        address oracleAddress,
        address vaultAddress
    )
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory)
    {
        IOracle oracleInstance = IOracle(oracleAddress);
        uint256 length = collectionAddresses.length;
        uint256[] memory prices = new uint256[](length);
        uint256[] memory volumes = new uint256[](length);
        uint256[] memory maximumOptionAmounts = new uint256[](length);

        uint256[2][] memory oracleGetAssetsReturnValue = oracleInstance
            .getAssets(collectionAddresses);
        IVault vaultInstance = IVault(vaultAddress);

        for (uint256 i = 0; i < length; i++) {
            prices[i] = oracleGetAssetsReturnValue[i][0];
            volumes[i] = oracleGetAssetsReturnValue[i][1];

            // maximumOptionAmounts[i] = 0;
            maximumOptionAmounts[i] = vaultInstance.maximumOptionAmount(
                collectionAddresses[i],
                OptionType.LONG_CALL
            );
        }

        return (prices, volumes, maximumOptionAmounts);
    }

    function getCollection(
        address collectionAddress,
        address oracleAddress,
        address vaultAddress
    ) external view returns (address, uint256, uint256, uint256) {
        address[] memory collectionAddresses = new address[](1);
        collectionAddresses[0] = collectionAddress;

        IOracle oracleInstance = IOracle(oracleAddress);
        uint256[2][] memory oracleGetAssetsReturnValue = oracleInstance
            .getAssets(collectionAddresses);

        IVault vaultInstance = IVault(vaultAddress);
        uint256 maximumOptionAmount = vaultInstance.maximumOptionAmount(
            collectionAddress,
            OptionType.LONG_CALL
        );
        // uint256 maximumOptionAmount = 0;

        return (
            collectionAddress,
            oracleGetAssetsReturnValue[0][0],
            oracleGetAssetsReturnValue[0][1],
            maximumOptionAmount
        );
    }
}
