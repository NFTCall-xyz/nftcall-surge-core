//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;


// TODO: Check Dopex code to find how they earn yield from other protocols
contract OptionMakerPool {
    // Pool config here
    uint16 totalCallOpenLimit = 9500;     // means 95% of whole pool. Left ETH will be used for user withdraw
    uint16 totalPutOpenLimit = 9500;      // as above, but for put
    uint16 exerciseFee = 125;              // means 1.25%. need a func to update it

    // Pool status here
    // LP token value will be calculated off chain, and updated on chain periodically
    // Make sure LP token value < totalETHinPool/tokenTotalNum * 1.1
    // Need LP token contract
    uint LPTokenValue;      // by Oracle
    // Used to store how much ETH has been used as collateral
    uint collateral;
    uint totalETHinPool;

    // Used to store Collection config & status
    struct CollectionInfo {
        uint16 openLimit;    // i.e., BYAC < 30%
        uint16 usedCollateral;      // current open ratio = usedCollateral / totalETHinPool
        int16 delta;                // also updated periodically, range from -1 to 1(here -10000 to 10000)
        uint16 floorPrice;          // as Oracle of nftcall
        uint16 vol;                 // as floorprice
    }

    // bayc, mayc, doodle, auzke...
    mapping(uint256 => CollectionInfo) private collectionInfos;

    // This func is used to deposit ETH and return LP token, for LPer
    // at beginning, LP token value = 1ETH
    function deposit() external {}

    // Used to withdraw ETH using LP token
    function withdraw() external {}

    // Open call
    // Parameters: underlying NFT collection, option amount, strikePrice gap, option duration, and more
    function openCall(uint8 collectionIdx, uint amount, uint strikePrice, uint duration) external {
        // 1. Check if allowed open: ETH collateral cannot exceed 95% of the whole pool, 
        // and cannot exceed the limit of this collection(i.e. BAYC < 30%)
        CollectionInfo memory ci = collectionInfos[collectionIdx];
        uint collateralNeeded = ci.floorPrice * amount;
        require(collateral + collateralNeeded <= totalETHinPool * totalCallOpenLimit);
        require(ci.usedCollateral + collateralNeeded <= totalETHinPool * ci.openLimit);
        // 2. Calculate Premium, based on Open Interest of this collection, and Delta(calculated off chain). TODO: Premium Func
        uint premium = getTunedPremium(collectionIdx);
        // 3. open: allocate collateral, charge Premium, and mint callToken to buyer
        collateral += collateralNeeded;
        // charge premium * count. 90% back to pool, 10% to protocol
        // mint optionToken to buyer
    }

    // Exercise call
    // This func will be called by buyer. We may provide European option and give buyers maybe 1H to exercise or we help them exercise with operation fee.
    // Or we provide American option which buyers can exercise anytime. But in case pool will be more risky to Oracle. User may take advantage of wrong Oracle.
    function exerciseCall() external {
        // Check buyer's PNL. If loss, exit
        // If profit: charge exercise fee(1.25% of exercise price), burn related callToken, and then send earned ETH to buyers
        // 1. require profit > 0 after subtracting exercise fee
        // 2. burn optionToken
        // 3. keep 10% exercise fee to protocol
        // 4. send profit to buyer, or add profit to users Balance?
    }

    // Premium function, as nftcall
    function getPremium(uint8 collectionIdx) public returns(uint premium) {
        return 1;
    }

    // Use Open Interest and Delta to tune Premium
    function getTunedPremium(uint8 collectionIdx) public returns(uint tunedPremium) {
        CollectionInfo memory ci = collectionInfos[collectionIdx];
        require(-1 <= ci.delta && ci.delta <= 1);
        // here call premium is different from put. call = premium(strikePrice120%) - premium(strikePrice220%)
        // we only provide capped call
        return getPremium(collectionIdx) * 2;
    }

    // Here openPut and exercisePut are same as above

    // Here are functions for configuring pool, or pause/unpause pool, withdraw protocol fee
}