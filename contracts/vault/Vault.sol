// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {DECIMALS, UNIT} from "../libraries/DataTypes.sol";
import {PERCENTAGE_FACTOR, PercentageMath} from "../libraries/math/PercentageMath.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {OptionType, OptionPosition, PositionState, IOptionToken} from "../interfaces/IOptionToken.sol";
import {TradeParameters, IOracle} from "../interfaces/IOracle.sol";
import {IPremium, PremiumVars} from "../interfaces/IPremium.sol";
import {IPricer} from "../interfaces/IPricer.sol";
import {IAssetRiskCache} from "../interfaces/IAssetRiskCache.sol";
import {OptionToken} from "../tokens/OptionToken.sol";

import "../interfaces/IVault.sol";

contract Vault is IVault, Pausable, Ownable{
    using StorageSlot for bytes32;
    using PercentageMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    address private _asset;
    address private _lpToken;
    address private _oracle;
    address private _riskCache;
    address private _pricer;
    address private _reserve;
    uint256 private _nextId = 1;    mapping(address => CollectionConfiguration) private _collections;
    mapping(uint256 => address) private _collectionsList;
    mapping(uint256 => Strike) private _strikes;

    uint256 private _collectionsCount;
    uint256 private _totalLockedAssets;
    int256 private _realizedPNL;
    uint256 private _unrealizedPremium;
    int256 private _unrealizedPNL;

    uint256 private constant RESERVE_RATIO = PERCENTAGE_FACTOR * 10 / 100; // 10%
    uint256 private FEE_RATIO =  PERCENTAGE_FACTOR * 5 / 1000; // 0.5%
    uint256 private MAXIMUM_FEE_RATIO = PERCENTAGE_FACTOR * 125 / 1000; // 12.5%
    uint256 public constant PREMIUM_UPSCALE_RATIO = PERCENTAGE_FACTOR * 150 / 100; // 150%
    
    uint256 public constant MAXIMUM_LOCK_RATIO = PERCENTAGE_FACTOR * 95 / 100; // 95%
    uint256 private constant _decimals = DECIMALS;

    uint256 public constant MAXIMUM_CALL_STRIKE_PRICE_RATIO = PERCENTAGE_FACTOR * 200 / 100; // 200%
    uint256 public constant MINIMUM_CALL_STRIKE_PRICE_RATIO = PERCENTAGE_FACTOR * 110 / 100; // 110%
    uint256 public constant MAXIMUM_PUT_STRIKE_PRICE_RATIO = PERCENTAGE_FACTOR * 90 / 100; // 90%
    uint256 public constant MINIMUM_PUT_STRIKE_PRICE_RATIO = PERCENTAGE_FACTOR * 50 / 100; // 50%

    uint256 public constant MINIMUM_DURATION = 3 days;
    uint256 public constant MAXIMUM_DURATION = 28 days;

    constructor (address asset, address lpToken, address oracle, address pricer, address riskCache, address reserve_)
        Ownable()
    {
        _asset = asset;
        _lpToken = lpToken;
        _oracle = oracle;
        _pricer = pricer;
        _riskCache = riskCache;
        _reserve = reserve_;
    }

    function reserve() public override view returns(address) {
        return _reserve;
    }

    function unrealizedPNL() public override view returns(int256) {
        return _unrealizedPNL;
    }

    //This function is used to update the unrealizedPNL variable in this contract
    //The unrealizedPNL is calculated by summing the unrealizedPNL for each asset in the vault
    function updateUnrealizedPNL() public override returns(int256){
        int256 newPNL = 0;
        for(uint256 i = 0; i < _collectionsCount; i++){
            address collection = _collectionsList[i];
            CollectionConfiguration storage config = _collections[collection];
            if(config.activated){
                (,int256 PNL) = IAssetRiskCache(_riskCache).getAssetRisk(collection);
                newPNL += PNL;
            }
        }
        _unrealizedPNL = newPNL;
        return newPNL;
    }

    function unrealizedPremium() public override view returns(uint256) {
        return _unrealizedPremium;
    }

    function deposit(uint256 amount, address onBehalfOf) public override{
        LPToken(_lpToken).deposit(amount, msg.sender, onBehalfOf);
    }

    function claimLPToken(address user) public override{
        LPToken(_lpToken).claim(user);
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

    function _validateOpenOption1(uint256 amount, OptionType optionType, Strike memory strike_) internal view{
        if(amount == 0){
            revert ZeroAmount(address(this));
        }
        if(optionType == OptionType.LONG_CALL){
            if(strike_.strikePrice > strike_.spotPrice.percentMul(MAXIMUM_CALL_STRIKE_PRICE_RATIO) 
               || strike_.strikePrice < strike_.spotPrice.percentMul(MINIMUM_CALL_STRIKE_PRICE_RATIO)){
                revert InvalidStrikePrice(address(this), strike_.strikePrice, strike_.spotPrice);
            }
        } else {
            if(strike_.strikePrice > strike_.spotPrice.percentMul(MAXIMUM_PUT_STRIKE_PRICE_RATIO) 
               || strike_.strikePrice < strike_.spotPrice.percentMul(MINIMUM_PUT_STRIKE_PRICE_RATIO)){
                revert InvalidStrikePrice(address(this), strike_.strikePrice, strike_.spotPrice);
            }
        }
        if(strike_.duration > MAXIMUM_DURATION || strike_.duration < MINIMUM_DURATION) {
            revert InvalidDuration(address(this), strike_.duration);
        } 
    }

    function _maximumLockedValueOfCollection(CollectionConfiguration memory collection, uint256 liquidity) internal pure returns (uint256){
        return liquidity.percentMul(collection.weight);
    }

    function _maximumLockedValue(uint256 liquidity) internal pure returns (uint256) {
        return liquidity.percentMul(MAXIMUM_LOCK_RATIO);
    }

    function _validateOpenOption2(CollectionConfiguration memory collection, uint256 valueToBeLocked, uint256 premium) internal view
    {
        uint256 currentAmount = IERC20(_asset).balanceOf(_lpToken) + premium;
        uint256 totalLockedValue = OptionToken(collection.optionToken).totalValue();
        if(totalLockedValue + valueToBeLocked > _maximumLockedValueOfCollection(collection, currentAmount)){
            revert InsufficientLiquidityForCollection(address(this), OptionToken(collection.optionToken).collection(), totalLockedValue, valueToBeLocked, currentAmount);
        }
        if(_totalLockedAssets + valueToBeLocked > _maximumLockedValue(currentAmount)){
            revert InsufficientLiquidity(address(this), _totalLockedAssets, valueToBeLocked, currentAmount);
        }
    }

    function maximumOptionAmount(address collection, OptionType optionType) external view override returns(uint256 amount) {
        CollectionConfiguration storage config = _collections[collection];
        uint256 currentAmount = IERC20(_asset).balanceOf(_lpToken);
        uint256 totalLockedValue = OptionToken(config.optionToken).totalValue();
        uint256 maximumLockedValueOfCollection = _maximumLockedValueOfCollection(config, currentAmount);
        if(totalLockedValue >= maximumLockedValueOfCollection){
            return 0;
        }
        uint256 maximumLockedValue = _maximumLockedValue(currentAmount);
        if(_totalLockedAssets >= maximumLockedValue){
            return 0;
        }
        uint256 spotPrice = IOracle(_oracle).getAssetPrice(collection);
        uint256 maximumOptionValue = Math.max(maximumLockedValueOfCollection - totalLockedValue, maximumLockedValue - _totalLockedAssets);
        amount = maximumOptionValue.mulDiv(UNIT, spotPrice, Math.Rounding.Down);
    }

    function strike(uint256 strikeId) public view override returns(Strike memory s){
        s = _strikes[strikeId];
        if(s.strikePrice == 0){
            revert InvalidStrikeId(address(this), strikeId);
        }
    }

    function _calculateStrikeAndPremium(address collection, OptionType optionType, Strike memory strike_) internal view returns(uint256 premium){
        IPricer pricer = IPricer(_pricer);
        uint256 adjustedVol = pricer.getAdjustedVol(collection, optionType, strike_.strikePrice);
        premium = pricer.getPremium(optionType, strike_.spotPrice, strike_.strikePrice, adjustedVol, strike_.duration).percentMul(PREMIUM_UPSCALE_RATIO);
    }

    //for options
    function openPosition(address collection, address onBehalfOf, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) public override 
        returns(uint256, uint256)
    {
        if(amount == 0){
            revert ZeroAmount(address(this));
        }
        CollectionConfiguration memory config = _collections[collection];
        Strike memory strike_;
        strike_.spotPrice = IOracle(_oracle).getAssetPrice(collection);
        strike_.strikePrice = strikePrice;
        strike_.expiry = expiry;
        strike_.duration = expiry - block.timestamp;
        _validateOpenOption1(amount, optionType, strike_);
        uint256 premium = _calculateStrikeAndPremium(collection, optionType, strike_);
        _validateOpenOption2(config, strike_.spotPrice.mulDiv(amount, UNIT, Math.Rounding.Up), premium);
        uint256 strikeId = _nextId++;
        _strikes[strikeId] = strike_;
        emit CreateStrike(strikeId, strike_.duration, strike_.expiry, strike_.spotPrice, strike_.strikePrice);
        //mint option token
        OptionToken optionToken = OptionToken(config.optionToken);
        uint256 positionId = optionToken.openPosition(onBehalfOf, optionType, strikeId, amount);
        _totalLockedAssets += optionToken.lockedValue(positionId);
        emit OpenPosition(collection, strikeId, positionId, premium);
        return (positionId, premium);
    }

    function activePosition(address collection, uint256 positionId) public override onlyOwner returns(uint256 premium){
        OptionToken optionToken = OptionToken(_collections[collection].optionToken);
        OptionPosition memory position = optionToken.optionPosition(positionId);
        Strike memory strike_ = _strikes[position.strikeId];
        TradeParameters memory tradeParameters;
        tradeParameters.optionType = position.optionType;
        tradeParameters.tradeType = TradeType.OPEN;
        tradeParameters.strikePrice = strike_.strikePrice;
        tradeParameters.duration = strike_.duration;
        tradeParameters.amount = position.amount;
        strike_.duration = strike_.expiry - block.timestamp;
        tradeParameters.expiry = strike_.expiry;
        strike_.spotPrice = IOracle(_oracle).getAssetPrice(collection);
        IPricer pricer = IPricer(_pricer);
        uint256 adjustedVol = pricer.getAdjustedVol(collection, position.optionType, strike_.strikePrice);
        premium = pricer.getPremium(position.optionType, strike_.spotPrice, strike_.strikePrice, adjustedVol, strike_.duration);
        _unrealizedPremium += premium;
        optionToken.activePosition(positionId, premium);
        //transfer premium from the caller to the vault
        uint256 amountToReserve = premium.percentMul(RESERVE_RATIO);
        _strikes[position.strikeId] = strike_;
        emit ReceivePremium(msg.sender, amountToReserve, premium - amountToReserve);
        IERC20(_asset).safeTransferFrom(msg.sender, _reserve, amountToReserve);
        IERC20(_asset).safeTransferFrom(msg.sender, _lpToken, premium - amountToReserve);
    }

    function closePosition(address collection, address to, uint256 positionId) public override onlyOwner returns(uint256 profit){
        //calculate fee
        //burn callOption token
        //transfer revenue from the vault to caller
        OptionToken optionToken = OptionToken(_collections[collection].optionToken);
        OptionPosition memory position = optionToken.optionPosition(positionId);
        
        // pending position
        if(position.state != PositionState.ACTIVE){
            revert PositionNotActive(address(this), positionId, position.state);
        }

        Strike memory strike_ = _strikes[position.strikeId];
        
        if(block.timestamp < strike_.expiry){
            revert PositionNotExpired(address(this), positionId, strike_.expiry, block.timestamp);
        }

        _totalLockedAssets -= optionToken.lockedValue(positionId);
        _unrealizedPremium -= position.premium;
        _realizedPNL += int256(position.premium);

        uint256 currentPrice = IOracle(_oracle).getAssetPrice(collection);
        TradeParameters memory tradeParameters;
        tradeParameters.optionType = position.optionType;
        tradeParameters.tradeType = TradeType.CLOSE;
        tradeParameters.spotPrice = strike_.spotPrice;
        tradeParameters.strikePrice = strike_.strikePrice;
        tradeParameters.duration = strike_.duration;
        tradeParameters.expiry = strike_.expiry;
        tradeParameters.amount = position.amount;
        // IOracle(_oracle).update(address(this), collection, tradeParameters);
        optionToken.closePosition(positionId);
        delete _strikes[position.strikeId];
        emit DestoryStrike(position.strikeId);
        uint256 fee;
        (profit, fee) = _calculateExerciseProfit(position.optionType, currentPrice, strike_.strikePrice, position.amount);
        if(profit != 0){
            _realizedPNL -= int256(profit + fee);
            IERC20(_asset).safeTransferFrom(_lpToken, _reserve, fee);
            IERC20(_asset).safeTransferFrom(_lpToken, to, profit);
            emit SendRevenue(to, profit, fee);
        }
        return profit;
    }

    function forceClosePendingPosition(address collection, uint256 positionId) public override onlyOwner {
        OptionToken optionToken = OptionToken(_collections[collection].optionToken);
        _totalLockedAssets -= optionToken.lockedValue(positionId);
        uint256 strikeId = optionToken.optionPosition(positionId).strikeId;
        delete _strikes[strikeId];
        emit DestoryStrike(strikeId);
        optionToken.forceClosePosition(positionId);
    }

    function _calculateExerciseProfit(OptionType optionType, uint256 currentPrice, uint256 strikePrice, uint256 amount) internal view returns(uint256, uint256){
        uint256 profit;
        if(optionType == OptionType.LONG_CALL){
            if(currentPrice <= strikePrice){
                return (0, 0);
            }
            profit = currentPrice - strikePrice;
            if(profit > strikePrice){
                profit = strikePrice;
            }
            profit = profit.mulDiv(amount, UNIT, Math.Rounding.Down);
        }
        else{
            if(currentPrice >= strikePrice) {
                return (0, 0);
            }
            profit = (strikePrice - currentPrice).mulDiv(amount, UNIT, Math.Rounding.Down);
        }
        uint256 fee = currentPrice.mulDiv(amount, UNIT, Math.Rounding.Down).percentMul(FEE_RATIO);
        uint256 maximumFee = profit.percentMul(MAXIMUM_FEE_RATIO);
        return (profit - Math.min(fee, maximumFee), maximumFee);
    }

    function addMarket(address collection, uint32 weight, address optionToken) public onlyOwner override returns(uint32){
        CollectionConfiguration memory collectionConfiguration = _collections[collection];
        if(collectionConfiguration.optionToken != address(0)){
            revert CollectionAlreadyExists(address(this), collection);
        }
        uint256 id = uint256(collectionConfiguration.id);
        if(id == 0 && _collectionsList[0] != collection){
            id = _collectionsCount;
            _collectionsList[_collectionsCount] = collection;
            _collectionsCount++;
        }

        _collections[collection] = CollectionConfiguration(false, true, uint32(id), weight, optionToken);
        emit CreateMarket(collection, weight, optionToken);
        return uint32(id);
    }

    function markets() public view override returns(address[] memory ) {
        address[] memory activeMarkets = new address[](_collectionsCount);
        for(uint256 i = 0; i < _collectionsCount; i++){
            activeMarkets[i] = _collectionsList[i];
        }
        return activeMarkets;
    }

    function marketConfiguration(address collection) public view returns(CollectionConfiguration memory) {
        return _collections[collection];
    }
}