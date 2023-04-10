// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {STRIKE_PRICE_GAP_LIST_SIZE, DURATION_LIST_SIZE} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {WadRayMath} from "../libraries/math/WadRayMath.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {TradeType, Strike, IVault} from "../interfaces/IVault.sol";
import {OptionType, OptionPosition, PositionState, IOptionBase} from "../interfaces/IOptionBase.sol";
import {TradeParameters, IOracle} from "../interfaces/IOracle.sol";
import {IPremium, PremiumVars} from "../interfaces/IPremium.sol";
import {CallOptionToken} from "../tokens/CallOptionToken.sol";
import {PutOptionToken} from "../tokens/PutOptionToken.sol";


contract Vault is IVault, Pausable, Ownable{
    using StorageSlot for bytes32;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using Math for uint256;

    struct CollectionConfiguration {
        bool paused;
        bool activated;
        uint16 weight; // percentage: 10000 means 100%
        address callToken;
        address putToken;
    }

    struct CollectionData {
        CollectionConfiguration config;
        int256 delta;
        int256 unrealizedPNL;
    }

    
    address private _asset;
    address private _lpToken;
    address private _oracle;
    address private _premium;
    address private _reserve;
    uint16 private _maximumCallUsage;
    uint16 private _maximumPutUsage;
    uint40 private _lastUpdateTimestamp;
    uint256 private _nextId = 1;
    mapping(address => CollectionData) private _collections;
    mapping(uint256 => address) private _collectionsList;
    mapping(uint256 => Strike) private _strikes;

    uint256 private _collectionsCount;
    uint256 private _totalLockedAssets;
    int256 private _realizedPNL;
    uint256 private _unrealizedPremium;
    int256 private _unrealizedPNL;

    uint256 private constant RESERVE_RATIO = 1000; // 10%
    uint256 private FEE_RATIO = 125; // 1.25%
    uint256 private MAXIMUM_FEE_RATIO = 1250; // 12.5%
    
    uint256 private constant MAXIMUM_LOCK_RATIO = 9500; // 95%
    uint256 private constant _decimals = 18;

    /**
     * @notice Get strike price gap
     * @param strikePriceGapIdx Index of strike price gap
     * @return uint256 Strike price gap
     */
    function STRIKE_PRICE_GAP(uint8 strikePriceGapIdx) public pure returns(uint256) {
        uint24[STRIKE_PRICE_GAP_LIST_SIZE] memory strikePriceGaps = [0, 1e4, 2*1e4, 3*1e4, 5*1e4, 1e5]; // [0% 10% 20% 30% 50% 100%]
        return uint256(strikePriceGaps[strikePriceGapIdx]);
    }

    /*
     * @notice Get duration
     * @param durationIdx Index of duration
     * @return uint40 Duration
     */
    function DURATION(uint8 durationIdx) public pure returns(uint256) {
        uint256[DURATION_LIST_SIZE] memory durations = [uint256(3 days), 7 days, 14 days, 28 days];
        return durations[durationIdx];
    }

    function unrealizedPNL() public override view returns(int256) {
        return _unrealizedPNL;
    }

    function unrealizedPremium() public override view returns(uint256) {
        return _unrealizedPremium;
    }

    function deposit(uint256 amount, address onBehalfOf) public override{
        LPToken(_lpToken).deposit(amount, onBehalfOf);
    }

    function withdraw(uint256 amount, address to) public override returns(uint256){
        return LPToken(_lpToken).withdraw(amount, to, msg.sender);
    }

    function totalAssets() public view override returns(uint256) {
        return LPToken(_lpToken).totalAssets();
    }

    function totalLockedAssets() public view override returns(uint256) {
        return _totalLockedAssets;
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

    function _validateOpenOption2(CollectionConfiguration memory collection, uint256 valueToBeLocked, uint256 premium) internal view
    {
        uint256 currentAmount = IERC20(_asset).balanceOf(_lpToken) + premium;
        if(_totalValue(collection) + valueToBeLocked > currentAmount.percentMul(collection.weight)){
            revert();
        }
        if(_totalLockedAssets + valueToBeLocked > currentAmount.percentMul(MAXIMUM_LOCK_RATIO)){
            revert();
        }
    }

    function strike(uint256 tokenId) public view override returns(Strike memory){
        return _strikes[tokenId];
    }

    function _calculateStrikeAndPremium(address collection, OptionType optionType, uint8 strikePriceIdx, uint8 durationIdx) internal view returns(Strike memory strike_, uint256 premium){
        uint256 vol;
        (strike_.spotPrice, vol) = IOracle(_oracle).getAssetPriceAndVol(collection);
        strike_.expiry = block.timestamp + DURATION(durationIdx);
        if(optionType == OptionType.LONG_CALL){
            strike_.strikePrice = _callStrikePrice(strike_.spotPrice, strikePriceIdx);
            premium = IPremium(_premium).getCallPremium(strike_.spotPrice, strike_.strikePrice, strike_.expiry, vol);
        }else{
            strike_.strikePrice = _putStrikePrice(strike_.spotPrice, strikePriceIdx);
            premium = IPremium(_premium).getPutPremium(strike_.spotPrice, strike_.strikePrice, strike_.expiry, vol);
        }
    }

    //for options
    function openCallPosition(address collection, address onBehalfOf, uint8 strikePriceIdx, uint8 durationIdx, uint256 amount) public override 
        returns(uint256, uint256)
    {
        CollectionData memory data = _collections[collection];
        CollectionConfiguration memory config = data.config;
        _validateOpenOption1(amount, strikePriceIdx, durationIdx);
        (Strike memory strike_, uint256 premium) = _calculateStrikeAndPremium(collection, OptionType.LONG_CALL, strikePriceIdx, durationIdx);
        _validateOpenOption2(config, strike_.spotPrice.mulDiv(amount, 10 ** _decimals, Math.Rounding.Up), premium);
        uint256 strikeId = _nextId++;
        _strikes[strikeId] = strike_;
        //mint callOption token
        return (CallOptionToken(config.callToken).openPosition(onBehalfOf, strikeId, amount), premium);
    }

    function activateCallPosition(address collection, uint256 positionId) public override onlyOwner returns(uint256 premium){
        CollectionConfiguration memory config = _collections[collection].config;
        CallOptionToken callToken = CallOptionToken(config.callToken);
        OptionPosition memory position = callToken.optionPosition(positionId);
        _totalLockedAssets += callToken.spotPrice(positionId).mulDiv(position.amount, 10 ** _decimals, Math.Rounding.Up);
        Strike memory strike_ = _strikes[position.strikeId];
        TradeParameters memory tradeParameters;
        tradeParameters.optionType = OptionType.LONG_CALL;
        tradeParameters.tradeType = TradeType.OPEN;
        tradeParameters.strikePrice = strike_.strikePrice;
        tradeParameters.expiry = strike_.expiry;
        tradeParameters.amount = position.amount;
        uint256 vol = IOracle(_oracle).updateAndGetVol(address(this), collection, tradeParameters);
        premium = IPremium(_premium).getCallPremium(strike_.spotPrice, strike_.strikePrice, strike_.expiry, vol);
        _unrealizedPremium += premium;
        callToken.activePosition(positionId, premium);
        //transfer premium from the caller to the vault
        uint256 amountToReserve = premium.percentMul(RESERVE_RATIO);
        _strikes[position.strikeId] = strike_;
        if(!IERC20(_asset).transferFrom(msg.sender, _reserve, amountToReserve)){
            revert();
        }
        if(!IERC20(_asset).transferFrom(msg.sender, _lpToken, premium - amountToReserve)){
            revert();
        }
    }

    function openPutPosition(address collection, address onBehalfOf, uint8 strikePriceIdx, uint8 durationIdx, uint256 amount) public override 
        returns(uint256, uint256)
    {
        CollectionData memory data = _collections[collection];
        CollectionConfiguration memory config = data.config;
        _validateOpenOption1(amount, strikePriceIdx, durationIdx);
        (Strike memory strike_, uint256 premium) = _calculateStrikeAndPremium(collection, OptionType.LONG_PUT, strikePriceIdx, durationIdx);
        _validateOpenOption2(config, strike_.strikePrice.mulDiv(amount, 10 ** _decimals, Math.Rounding.Up), premium);
        uint256 strikeId = _nextId++;
        _strikes[strikeId] = strike_;
        //mint putOption token
        return (PutOptionToken(config.putToken).openPosition(onBehalfOf, strikeId, amount), premium);
    }

    function activatePutPosition(address collection, uint256 positionId) public override onlyOwner returns(uint256 premium){
        CollectionConfiguration memory config = _collections[collection].config;
        PutOptionToken putToken = PutOptionToken(config.putToken);
        
        OptionPosition memory position = putToken.optionPosition(positionId);
        _totalLockedAssets += putToken.strikePrice(positionId).mulDiv(position.amount, 10 ** _decimals, Math.Rounding.Up);
        Strike memory strike_ = _strikes[position.strikeId];
        TradeParameters memory tradeParameters;
        tradeParameters.optionType = OptionType.LONG_PUT;
        tradeParameters.tradeType = TradeType.OPEN;
        tradeParameters.strikePrice = strike_.strikePrice;
        tradeParameters.expiry = strike_.expiry;
        tradeParameters.amount = position.amount;
        uint256 vol = IOracle(_oracle).updateAndGetVol(address(this), collection, tradeParameters);
        premium = IPremium(_premium).getPutPremium(strike_.spotPrice, strike_.strikePrice, strike_.expiry, vol);
        _unrealizedPremium += premium;
        //transfer premium from the caller to the vault
        uint256 amountToReserve = premium.percentMul(RESERVE_RATIO);
        _strikes[position.strikeId] = strike_;
        putToken.activePosition(positionId, premium);
        if(!IERC20(_asset).transferFrom(msg.sender, _reserve, amountToReserve)){
            revert();
        }
        if(!IERC20(_asset).transferFrom(msg.sender, _lpToken, premium - amountToReserve)){
            revert();
        }
    }

    function closeCallPosition(address collection, address to, uint256 positionId) public override onlyOwner returns(uint256 profit){
        //calculate fee
        //burn callOption token
        //transfer revenue from the vault to caller
        CollectionConfiguration memory config = _collections[collection].config;
        CallOptionToken callToken = CallOptionToken(config.callToken);
        OptionPosition memory position = callToken.optionPosition(positionId);
        // pending position
        if(position.state != PositionState.ACTIVE){
            callToken.forceClosePosition(positionId);
            return 0;
        }

        Strike memory strike_ = _strikes[position.strikeId];
        
        if(block.timestamp < strike_.expiry){
            revert();
        }
        _totalLockedAssets -= callToken.spotPrice(positionId);
        _unrealizedPremium -= position.premium;
        _realizedPNL += int256(position.premium);

        uint256 currentPrice = IOracle(_oracle).getAssetPrice(collection);
        TradeParameters memory tradeParameters;
        tradeParameters.optionType = OptionType.LONG_PUT;
        tradeParameters.tradeType = TradeType.CLOSE;
        tradeParameters.spotPrice = strike_.spotPrice;
        tradeParameters.strikePrice = strike_.strikePrice;
        tradeParameters.expiry = strike_.expiry;
        tradeParameters.amount = position.amount;
        IOracle(_oracle).update(address(this), collection, tradeParameters);
        callToken.closePosition(positionId);
        delete _strikes[position.strikeId];

        profit = _calculateExerciseCallProfit(currentPrice, strike_.strikePrice, position.amount);
        if(profit != 0){
            _realizedPNL -= int256(profit);
            if(!IERC20(_asset).transfer(to, profit)){
                revert();
            }
        }
        return profit;
    }

    function closePutPosition(address collection, address to, uint256 positionId) public override onlyOwner returns(uint256 profit){
        //calculate fee
        //burn putOption token
        //transfer revenue from the vault to caller
        CollectionConfiguration memory config = _collections[collection].config;
        PutOptionToken putToken = PutOptionToken(config.putToken);
        OptionPosition memory position = putToken.optionPosition(positionId);
        // pending position
        if(position.state != PositionState.ACTIVE){
            putToken.forceClosePosition(positionId);
            return 0;
        }

        Strike memory strike_ = _strikes[position.strikeId];
        
        if(block.timestamp < strike_.expiry){
            revert();
        }
        _totalLockedAssets -= putToken.strikePrice(positionId).mulDiv(position.amount, 10 ** _decimals, Math.Rounding.Up);
        _unrealizedPremium -= position.premium;
        _realizedPNL += int256(position.premium);

        uint256 currentPrice = IOracle(_oracle).getAssetPrice(collection);
        TradeParameters memory tradeParameters;
        tradeParameters.optionType = OptionType.LONG_PUT;
        tradeParameters.tradeType = TradeType.CLOSE;
        tradeParameters.spotPrice = strike_.spotPrice;
        tradeParameters.strikePrice = strike_.strikePrice;
        tradeParameters.expiry = strike_.expiry;
        tradeParameters.amount = position.amount;
        IOracle(_oracle).update(address(this), collection, tradeParameters);
        putToken.closePosition(positionId);
        delete _strikes[position.strikeId];

        profit = _calculateExercisePutProfit(currentPrice, strike_.strikePrice, position.amount);
        if(profit != 0){
            _realizedPNL -= int256(profit);
            if(!IERC20(_asset).transfer(to, profit)){
                revert();
            }
        }
        return profit;
    }

    /*function previewOpenCall(address collection, uint256 amount, uint256 strikePriceIdx, uint256 durationIdx) external view returns(uint256 strikePrice, uint256 premium, uint256 errorCode) {


    }

    function previewOpenPut(address collection, uint256 amount, uint256 strikePriceIdx, uint256 durationIdx) external view returns(uint256 strikePrice, uint256 premium, uint256 errorCode) {

    }*/

    function updatePNLAndDelta() public {
        _updatePNL();
        _updateDelta();
        _lastUpdateTimestamp = uint40(IOracle(_oracle).getUpdateTimestampForVaultData(address(this)));
    }

    function _updatePNL() internal {
        int256 totalPNL = 0;
        // update all collections' PNL
        for(uint256 i = 0; i < _collectionsCount; i++){
            address collection = _collectionsList[i];
            CollectionData memory collectionData = _collections[collection];
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
            CollectionData memory collectionData = _collections[collection];
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
        profit = profit.mulDiv(amount, 10 ** _decimals, Math.Rounding.Down);
        uint256 fee = currentPrice.mulDiv(amount, 10 ** _decimals, Math.Rounding.Down).percentMul(FEE_RATIO);
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
        uint256 profit = (strikePrice - currentPrice).mulDiv(amount, 10 ** _decimals, Math.Rounding.Down);
        uint256 fee = currentPrice.mulDiv(amount, 10**_decimals, Math.Rounding.Down).percentMul(FEE_RATIO);
        uint256 maximumFee = profit.percentMul(MAXIMUM_FEE_RATIO);
        if(fee > maximumFee){
            return profit - maximumFee;
        }
        else {
            return profit - fee;
        }
    }

    function _totalValue(CollectionConfiguration memory collectionData) internal view returns(uint256){
        return CallOptionToken(collectionData.callToken).totalValue()  + PutOptionToken(collectionData.putToken).totalValue();
    }

    function _callStrikePrice(uint256 currentPrice, uint8 strikePriceGapIndex) internal pure returns(uint256){
        return currentPrice.percentMul(PercentageMath.PERCENTAGE_FACTOR + STRIKE_PRICE_GAP(strikePriceGapIndex));
    }

    function _putStrikePrice(uint256 currentPrice, uint8 strikePriceGapIndex) internal pure returns(uint256){
        return currentPrice.percentMul(PercentageMath.PERCENTAGE_FACTOR - STRIKE_PRICE_GAP(strikePriceGapIndex));
    }

    function _strikePrice(OptionType optionType, uint256 spotPrice, uint8 strikePriceGapIndex) internal pure returns(uint256) {
        if(optionType == OptionType.LONG_CALL){
            return _callStrikePrice(spotPrice, strikePriceGapIndex);
        }
        else {
            return _putStrikePrice(spotPrice, strikePriceGapIndex);
        }
    }
}