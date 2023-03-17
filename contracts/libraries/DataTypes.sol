// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

uint256 constant STRIKE_PRICE_GAP_LIST_SIZE = 6;
uint256 constant DURATION_LIST_SIZE = 4;

library DataTypes {
    struct OptionData {
        uint8 optionType; // 0 - call, 1 - put
        uint8 strikePriceGapIndex;
        uint8 durationIndex;
        address collection;
        uint256 amount;
        uint256 expirationTime;
        uint256 openPrice;
    }

    struct CollectionConfiguration {
        bool paused;
        bool activated;
        uint16 weight; // percentage: 10000 means 100%
        address callToken;
        address putToken;
        address premium;
    }

    struct CollectionData {
        CollectionConfiguration config;
        uint256 delta;
        int256 unrealizedPNL;
    }

}