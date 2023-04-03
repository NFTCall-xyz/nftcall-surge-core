// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {STRIKE_PRICE_GAP_LIST_SIZE, DURATION_LIST_SIZE, DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {WadRayMath} from "../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {IOptionBase} from "../interfaces/IOptionBase.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPremium, PremiumVars} from "../interfaces/IPremium.sol";
import {CallOptionToken} from "../tokens/CallOptionToken.sol";
import {PutOptionToken} from "../tokens/PutOptionToken.sol";


contract Vault is Pausable{
    using StorageSlot for bytes32;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    address private _asset;
    address private _lpToken;
    address private _oracle;
    address private _reserve;
    uint16 private _maximumCallUsage;
    uint16 private _maximumPutUsage;
    uint40 private _lastUpdateTimestamp;
    uint256 private _nextTokenId;
    mapping(address => DataTypes.CollectionData) private _collections;
    mapping(uint256 => address) private _collectionsList;
    mapping(uint256 => DataTypes.OptionData) private _options;

    uint256 private _collectionsCount;
    uint256 private _currentCallUsage;
    uint256 private _currentPutUsage;
    uint256 private _totalLockedValue;
    uint256 private _maximumVaultSize;
    int256 private _realizedPNL;
    int256 private _unrealizedPNL;

    uint256 private constant RESERVE_RATIO = 1000; // 10%
    uint256 private FEE_RATIO = 125; // 1.25%
    uint256 private MAXIMUM_FEE_RATIO = 1250; // 12.5%
    uint256 private constant MAXIMUM_WITHDRAW_RATIO = 5000; // 50%
    uint256 private constant MAXIMUM_LOCK_RATIO = 9500; // 95%

    function STRIKE_PRICE_GAP(uint8 strikePriceGapIdx) public pure returns(uint256) {
        uint24[STRIKE_PRICE_GAP_LIST_SIZE] memory strikePriceGaps = [0, 1e4, 2*1e4, 3*1e4, 5*1e4, 1e5]; // [0% 10% 20% 30% 50% 100%]
        return uint256(strikePriceGaps[strikePriceGapIdx]);
    }

    function DURATION(uint8 durationIdx) public pure returns(uint40) {
        uint40[DURATION_LIST_SIZE] memory durations = [uint40(3 days), uint40(7 days), uint40(14 days), uint40(28 days)];
        return uint40(durations[durationIdx]);
    }

    function PNL() public view returns(int256) {
        return _unrealizedPNL;
    }

    function deposit(uint256 amount, address onBehalfOf) public {
        // check if amount is 0
        if(amount == 0) {
            revert();
        }
        // check if the sum of all lpTokens and amount is greater than the upper limit
        if(LPToken(_lpToken).totalSupply() + amount > _maximumVaultSize) {
            revert();
        }
        //mint NLP token
        //transfer _asset from caller to the NLP token
        LPToken(_lpToken).mint(onBehalfOf, amount);
    }

    function withdraw(uint256 amount, address to) public returns(uint256){
        // check if amount is 0
        if(amount == 0) {
            revert();
        }

        address user = msg.sender;
        uint256 userBalance = _getMaximumWithdrawAmount(user);
        uint256 amountToWithdraw = amount;
        if(amount == type(uint256).max){
            amountToWithdraw = userBalance;
        }

        // check if the amount is greater than the maximum withdrawable amount
        if(amount > userBalance){
            revert();
        }

        //burn NLP token
        //transfer _asset from the NLP token to caller
        LPToken(_lpToken).burn(msg.sender, to, amountToWithdraw);
        return(amountToWithdraw);
    }

    // The maximum withdrawable amount is the minimum of the user's unlocked balance 
    // and the maximum withdrawable amount calculated by the formula below:
    // (total asset balance - total locked value) * MAXIMUM_WITHDRAW_RATIO / 10000
    function _getMaximumWithdrawAmount(address user) internal view returns(uint256) {
        
        LPToken lpToken = LPToken(_lpToken);
        uint256 userBalance = lpToken.balanceOf(user) - lpToken.lockedBalanceOf(user);
        if(userBalance == 0) {
            revert();
        }
        userBalance = lpToken.convertToAssets(userBalance);
        uint256 maximumWithdrawBalance = (IERC20(_asset).balanceOf(_lpToken) - _totalLockedValue).percentMul(MAXIMUM_WITHDRAW_RATIO);
        return (userBalance > maximumWithdrawBalance) ? maximumWithdrawBalance : userBalance;
    }

    function _validateOpenOption1(uint256 amount, uint8 strikePriceIdx, uint8 durationIdx) internal pure {
        if(amount == 0){
            revert();
        }
        if(strikePriceIdx >= STRIKE_PRICE_GAP_LIST_SIZE) {
            revert();
        }
        if(durationIdx >= DURATION_LIST_SIZE) {
            revert();
        } 
    }

    function _validateOpenOption2(DataTypes.CollectionConfiguration storage collection, uint256 valueToBeLocked, uint256 premium) internal view
    {
        uint256 currentAmount = IERC20(_asset).balanceOf(_lpToken) + premium;
        if(_totalValue(collection) + valueToBeLocked > currentAmount.percentMul(collection.weight)){
            revert();
        }
        if(_totalLockedValue + valueToBeLocked > currentAmount.percentMul(MAXIMUM_LOCK_RATIO)){
            revert();
        }
    }

    //for options
    function openCall(address collection, address onBehalfOf, uint256 amount, uint8 strikePriceIdx, uint8 durationIdx) public returns(uint256 tokenId){
        _validateOpenOption1(amount, strikePriceIdx, durationIdx);
        DataTypes.CollectionConfiguration storage config = _collections[collection].config;
        DataTypes.CollectionData memory data = _collections[collection];
        //calculate premium
        (uint256 currentPrice, uint256 vol) = IOracle(_oracle).getAssetPriceAndVol(collection);
        uint256 premium = _calculateCallPremium(data, currentPrice, vol, amount, strikePriceIdx, durationIdx);
        uint256 strikePrice = _callStrikePrice(currentPrice, strikePriceIdx);
        uint256 valueToBeLocked = currentPrice.wadMul(amount);
        uint40 expirationTime = uint40(block.timestamp) + DURATION(durationIdx);
        _validateOpenOption2(config, valueToBeLocked, premium);
        _totalLockedValue += valueToBeLocked;
        _collections[collection] = data;
        //mint callOption token
        tokenId = _addNewToken();
        _options[tokenId] = DataTypes.OptionData(2, strikePriceIdx, durationIdx, collection, amount, expirationTime, currentPrice, premium);
        CallOptionToken(config.callToken).mint(onBehalfOf, strikePriceIdx, durationIdx, expirationTime, strikePrice, tokenId, amount);
        //transfer premium from the caller to the vault
        uint256 amountToReserve = premium.percentMul(RESERVE_RATIO);
        if(!IERC20(_asset).transferFrom(msg.sender, _reserve, amountToReserve)){
            revert();
        }
        if(!IERC20(_asset).transferFrom(msg.sender, _lpToken, premium - amountToReserve)){
            revert();
        }
        //return the tokenId
    }

    function openPut(address collection, address onBehalfOf, uint256 amount, uint8 strikePriceIdx, uint8 durationIdx) public returns(uint256 tokenId){
        _validateOpenOption1(amount, strikePriceIdx, durationIdx);
        DataTypes.CollectionConfiguration storage config = _collections[collection].config;
        DataTypes.CollectionData memory data = _collections[collection];
        //calculate premium
        (uint256 currentPrice, uint256 vol) = IOracle(_oracle).getAssetPriceAndVol(collection);
        uint256 premium = _calculatePutPremium(data, currentPrice, vol, amount, strikePriceIdx, durationIdx);
        uint256 strikePrice = _putStrikePrice(currentPrice, strikePriceIdx);
        uint256 valueToBeLocked = strikePrice.wadMul(amount);
        uint40 expirationTime = uint40(block.timestamp) + DURATION(durationIdx);
        _validateOpenOption2(config, valueToBeLocked, premium);
        _totalLockedValue += valueToBeLocked;
        _collections[collection] = data;
        //mint putOption token
        tokenId = _addNewToken();
        _options[tokenId] = DataTypes.OptionData(3, strikePriceIdx, durationIdx, collection, amount, expirationTime, currentPrice, premium);
        PutOptionToken(config.putToken).mint(onBehalfOf, strikePriceIdx, durationIdx, expirationTime, strikePrice, tokenId, amount);
        //transfer premium from the caller to the vault
        uint256 amountToReserve = premium.percentMul(RESERVE_RATIO);
        if(!IERC20(_asset).transferFrom(msg.sender, _reserve, amountToReserve)){
            revert();
        }
        if(!IERC20(_asset).transferFrom(msg.sender, _lpToken, premium - amountToReserve)){
            revert();
        }
        //return the tokenId
    }

    // TODO added batch operations for exercise

    function exerciseCall(address collection, address to, uint256 tokenId) public returns(uint256 profit){
        //calculate fee
        //burn callOption token
        //transfer revenue from the vault to caller
        DataTypes.CollectionData memory collectionData = _collections[collection];
        DataTypes.OptionData storage optionData = _options[tokenId];
        if(block.timestamp < optionData.expiration) {
            revert();
        }
        uint256 currentPrice = IOracle(_oracle).getAssetPrice(collection);
        uint256 strikePrice = _strikePrice(optionData);
        profit = _calculateExerciseCallProfit(currentPrice, strikePrice, optionData.amount);
        _totalLockedValue -= optionData.openPrice.wadMul(optionData.amount);
        _realizedPNL += int256(_options[tokenId].premium);
        delete _options[tokenId];
        CallOptionToken(collectionData.config.callToken).burn(tokenId);
        if(profit != 0){
            _realizedPNL -= int256(profit);
            _collections[collection] = collectionData;
            if(!IERC20(_asset).transferFrom(_lpToken, to, profit)){
                revert();
            }
        }
    }

    function exercisePut(address collection, address to, uint256 tokenId) public returns(uint256 profit){
        //calculate fee
        //burn putOption token
        //transfer revenue from the vault to caller
        //calculate fee
        //burn callOption token
        //transfer revenue from the vault to caller
        DataTypes.CollectionData memory collectionData = _collections[collection];
        DataTypes.OptionData storage optionData = _options[tokenId];
        if(block.timestamp < optionData.expiration) {
            revert();
        }
        uint256 currentPrice = IOracle(_oracle).getAssetPrice(collection);
        uint256 strikePrice = _strikePrice(optionData);
        profit = _calculateExercisePutProfit(currentPrice, strikePrice, optionData.amount);
        _totalLockedValue -= strikePrice.wadMul(optionData.amount);
        _realizedPNL += int256(_options[tokenId].premium);
        delete _options[tokenId];
        PutOptionToken(collectionData.config.putToken).burn(tokenId);
        if(profit != 0){
            _realizedPNL -= int256(profit);
            _collections[collection] = collectionData;
            if(!IERC20(_asset).transferFrom(_lpToken, to, profit)){
                revert();
            }
        }
    }

    /*function previewOpenCall(address collection, uint256 amount, uint256 strikePriceIdx, uint256 durationIdx) external view returns(uint256 strikePrice, uint256 premium, uint256 errorCode) {


    }

    function previewOpenPut(address collection, uint256 amount, uint256 strikePriceIdx, uint256 durationIdx) external view returns(uint256 strikePrice, uint256 premium, uint256 errorCode) {

    }*/

    function _updatePNLAndDelta() public {
        _updatePNL();
        _updateDelta();
        _lastUpdateTimestamp = uint40(IOracle(_oracle).getUpdateTimestampForVaultData(address(this));
    }

    function _updatePNL() internal {
        int256 totalPNL = 0;
        // update all collections' PNL
        for(uint256 i = 0; i < _collectionsCount; i++){
            address collection = _collectionsList[i];
            DataTypes.CollectionData memory collectionData = _collections[collection];
            // TODO should not use the Oracle, because it is not the same for all Vaults.
            int256 newPNL = IOracle(_oracle).getPNL(address(this), collection);
            totalPNL += newPNL;
            _updatePNL(collection, newPNL);
        }
        _unrealizedPNL = totalPNL;
    }

    function _updatePNL(address collection, int256 newPNL) internal {
        // update the new PNL
        _collections[collection].unrealizedPNL = newPNL;
    }

    function _updateDelta() internal {
        // update all collections' PNL
        for(uint256 i = 0; i < _collectionsCount; i++){
            address collection = _collectionsList[i];
            DataTypes.CollectionData memory collectionData = _collections[collection];
            // TODO should not use the Oracle, because it is not the same for all Vaults.
            int256 newDelta = IOracle(_oracle).getDelta(address(this), collection);
            _updateDelta(collection, newDelta);
        }
    }

    function _updateDelta(address collection, int256 delta) internal {
        _collections[collection].delta = delta;
    }

    function _calculateExerciseCallProfit(uint256 currentPrice, uint256 strikePrice, uint256 amount) internal view returns(uint256){
        if(currentPrice <= strikePrice) {
            return 0;
        }
        uint256 profit = currentPrice - strikePrice;
        if(profit > strikePrice){
            profit = strikePrice;
        }
        profit = profit.wadMul(amount);
        uint256 fee = currentPrice.wadMul(amount).percentMul(FEE_RATIO);
        uint256 maximumFee = profit.percentMul(MAXIMUM_FEE_RATIO);
        if(fee > maximumFee){
            return profit - maximumFee;
        }
        else {
            return profit - fee;
        }
    }

    function _calculateExercisePutProfit(uint256 currentPrice, uint256 strikePrice, uint256 amount) internal view returns(uint256){
        if(currentPrice >= strikePrice) {
            return 0;
        }
        uint256 profit = (strikePrice - currentPrice).wadMul(amount);
        uint256 fee = currentPrice.wadMul(amount).percentMul(FEE_RATIO);
        uint256 maximumFee = profit.percentMul(MAXIMUM_FEE_RATIO);
        if(fee > maximumFee){
            return profit - maximumFee;
        }
        else {
            return profit - fee;
        }
    }

    function _calculateCallPremium(DataTypes.CollectionData memory collection, uint256 currentPrice, uint256 vol, uint256 amount, uint8 strikePriceGapIndex, uint8 durationIndex) internal view returns(uint256 premium ) {
        uint256 totalBalance = IERC20(_asset).balanceOf(_lpToken);
        uint16 vaultUtilization = uint16(_totalLockedValue.percentDiv(totalBalance));
        uint256 collectionLockedValue = CallOptionToken(collection.config.callToken).totalValue() + PutOptionToken(collection.config.putToken).totalValue();
        uint16 collectionUtilization = uint16(collectionLockedValue.percentDiv(totalBalance).percentDiv(collection.config.weight));
        PremiumVars memory vars = PremiumVars(strikePriceGapIndex, durationIndex, vaultUtilization, collectionUtilization, currentPrice, vol, amount, collection.delta, collection.realizedPNL);
        return IPremium(collection.config.premium).getCallPremium(vars);
    }

    function _calculatePutPremium(DataTypes.CollectionData memory collection, uint256 currentPrice, uint256 vol, uint256 amount, uint8 strikePriceGapIndex, uint8 durationIndex) internal view returns(uint256 premium ) {
        uint256 totalBalance = IERC20(_asset).balanceOf(_lpToken);
        uint16 vaultUtilization = uint16(_totalLockedValue.percentDiv(totalBalance));
        uint256 collectionLockedValue = CallOptionToken(collection.config.callToken).totalValue() + PutOptionToken(collection.config.putToken).totalValue();
        uint16 collectionUtilization = uint16(collectionLockedValue.percentDiv(totalBalance).percentDiv(collection.config.weight));
        PremiumVars memory vars = PremiumVars(strikePriceGapIndex, durationIndex, vaultUtilization, collectionUtilization, currentPrice, vol, amount, collection.delta, collection.realizedPNL);
        return IPremium(collection.config.premium).getPutPremium(vars);
    }

    function _totalValue(DataTypes.CollectionConfiguration storage collectionData) internal view returns(uint256){
        return CallOptionToken(collectionData.callToken).totalValue() + PutOptionToken(collectionData.putToken).totalValue();
    }

    function _addNewToken() internal returns (uint256 tokenId) {
        tokenId = _nextTokenId;
        _nextTokenId += 1;
    }

    function _callStrikePrice(uint256 currentPrice, uint8 strikePriceGapIndex) internal pure returns(uint256){
        return currentPrice.percentMul(PercentageMath.PERCENTAGE_FACTOR + STRIKE_PRICE_GAP(strikePriceGapIndex));
    }

    function _putStrikePrice(uint256 currentPrice, uint8 strikePriceGapIndex) internal pure returns(uint256){
        return currentPrice.percentMul(PercentageMath.PERCENTAGE_FACTOR - STRIKE_PRICE_GAP(strikePriceGapIndex));
    }

    function _strikePrice(DataTypes.OptionData storage optionData) internal view returns(uint256) {
        if(optionData.optionType == 0){
            return _callStrikePrice(optionData.openPrice, optionData.strikePriceGapIndex);
        }
        else {
            return _putStrikePrice(optionData.openPrice, optionData.strikePriceGapIndex);
        }
    }
}