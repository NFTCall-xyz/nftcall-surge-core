// SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {GENERAL_UNIT, DECIMALS, UNIT, HIGH_PRECISION_UNIT} from "../libraries/DataTypes.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {OptionType, OptionPosition, PositionState, IOptionToken} from "../interfaces/IOptionToken.sol";
import {TradeParameters, IOracle} from "../interfaces/IOracle.sol";
import {IPremium, PremiumVars} from "../interfaces/IPremium.sol";
import {IPricer} from "../interfaces/IPricer.sol";
import {IAssetRiskCache} from "../interfaces/IAssetRiskCache.sol";
import {OptionToken} from "../tokens/OptionToken.sol";

import "../interfaces/IVault.sol";

import "hardhat/console.sol";

contract Vault is IVault, Pausable, Ownable{
    using StorageSlot for bytes32;
    using Math for uint256;
    using SafeERC20 for IERC20;

    bool private _paused;
    address private _asset;
    address private _lpToken;
    address private _oracle;
    address private _riskCache;
    address private _pricer;
    address private _reserve;
    address private _backstopPool;
    address private _keeper;
    uint256 private _nextId = 1;    mapping(address => CollectionConfiguration) private _collections;
    mapping(uint256 => address) private _collectionsList;
    mapping(uint256 => Strike) private _strikes;

    uint256 private _collectionsCount;
    uint256 private _totalLockedAssets;
    int256 private _realizedPNL;
    uint256 private _unrealizedPremium;
    int256 private _unrealizedPNL;

    
    uint256 private FEE_RATIO =  GENERAL_UNIT * 5 / 1000; // 0.5%
    uint256 private PROFIT_FEE_RATIO = GENERAL_UNIT * 125 / 1000; // 12.5%
        
    uint256 private constant _decimals = DECIMALS;

    uint256 public override constant RESERVE_RATIO = GENERAL_UNIT * 10 / 100; // 10%
    uint256 public override constant MAXIMUM_LOCK_RATIO = GENERAL_UNIT * 95 / 100; // 95%

    uint256 public override constant MAXIMUM_CALL_STRIKE_PRICE_RATIO = GENERAL_UNIT * 200 / 100; // 200%
    uint256 public override constant MINIMUM_CALL_STRIKE_PRICE_RATIO = GENERAL_UNIT * 110 / 100; // 110%
    uint256 public override constant MAXIMUM_PUT_STRIKE_PRICE_RATIO = GENERAL_UNIT * 90 / 100; // 90%
    uint256 public override constant MINIMUM_PUT_STRIKE_PRICE_RATIO = GENERAL_UNIT * 50 / 100; // 50%
    uint256 public override constant KEEPER_FEE = 5 * 10**13; // 0.00005 ETH

    uint256 public override constant MINIMUM_DURATION = 3 days;
    uint256 public override constant MAXIMUM_DURATION = 30 days;

    constructor (address asset, address lpToken, address oracle, address pricer, address riskCache, address reserve_, address backstopPool_)
        Ownable()
    {
        _asset = asset;
        _lpToken = lpToken;
        _oracle = oracle;
        _pricer = pricer;
        _riskCache = riskCache;
        _reserve = reserve_;
        _backstopPool = backstopPool_;
        _keeper = owner();
    }

    modifier onlyKeeper() {
        if (msg.sender != _keeper) {
            revert OnlyKeeper(address(this), msg.sender, _keeper);
        }
        _;
    }

    modifier onlyUnpaused() {
        if (_paused) {
            revert OnlyUnpaused(address(this), msg.sender);
        }
        _;
    }

    function keeper() public override view returns(address) {
        return _keeper;
    }

    function setKeeper(address keeperAddress) public override onlyOwner {
        _keeper = keeperAddress;
    }

    function reserve() public override view returns(address) {
        return _reserve;
    }

    function backstopPool() public override view returns(address) {
        return _backstopPool;
    }

    function pause() public override onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public override onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function isPaused() public override view returns(bool) {
        return _paused;
    }

    function activateMarket(address collection) public override onlyOwner {
        _collections[collection].activated = true;
        emit ActivateMarket(msg.sender, collection);
    }

    function deactivateMarket(address collection) public override onlyOwner {
        _collections[collection].activated = false;
        emit DeactivateMarket(msg.sender, collection);
    }

    function isActiveMarket(address collection) public override view returns(bool) {
        return _collections[collection].activated;
    }

    function freezeMarket(address collection) public override onlyOwner {
        _collections[collection].frozen = true;
        emit FreezeMarket(msg.sender, collection);
    }

    function defreezeMarket(address collection) public override onlyOwner {
        _collections[collection].frozen = false;
        emit DefreezeMarket(msg.sender, collection);
    }

    function isFrozenMarket(address collection) public override view returns(bool) {
        return _collections[collection].frozen;
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
            CollectionConfiguration memory config = _collections[collection];
            if(config.activated){
                (,int256 PNL) = IAssetRiskCache(_riskCache).getAssetRisk(collection);
                newPNL += PNL;
            }
        }
        _unrealizedPNL = newPNL;
        uint256 price = LPToken(_lpToken).convertToAssets(HIGH_PRECISION_UNIT);
        emit UpdateLPTokenPrice(_lpToken, price);
        return newPNL;
    }

    function unrealizedPremium() public override view returns(uint256) {
        return _unrealizedPremium;
    }

    function feeRatio() public override view returns(uint256) {
        return FEE_RATIO;
    }

    function profitFeeRatio() public override view returns(uint256) {
        return PROFIT_FEE_RATIO;
    }

    function deposit(uint256 amount, address onBehalfOf) public override onlyUnpaused{
        LPToken(_lpToken).deposit(amount, msg.sender, onBehalfOf);
    }

    function withdraw(uint256 amount, address to) public override onlyUnpaused returns(uint256){
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
            if(strike_.strikePrice > strike_.spotPrice.mulDiv(MAXIMUM_CALL_STRIKE_PRICE_RATIO, GENERAL_UNIT, Math.Rounding.Down) 
               || strike_.strikePrice < strike_.spotPrice.mulDiv(MINIMUM_CALL_STRIKE_PRICE_RATIO, GENERAL_UNIT, Math.Rounding.Up)){
                revert InvalidStrikePrice(address(this), strike_.strikePrice, strike_.spotPrice);
            }
        } else {
            if(strike_.strikePrice > strike_.spotPrice.mulDiv(MAXIMUM_PUT_STRIKE_PRICE_RATIO, GENERAL_UNIT, Math.Rounding.Down) 
               || strike_.strikePrice < strike_.spotPrice.mulDiv(MINIMUM_PUT_STRIKE_PRICE_RATIO, GENERAL_UNIT, Math.Rounding.Up)){
                revert InvalidStrikePrice(address(this), strike_.strikePrice, strike_.spotPrice);
            }
        }
        if(strike_.duration > MAXIMUM_DURATION || strike_.duration < MINIMUM_DURATION) {
            revert InvalidDuration(address(this), strike_.duration);
        } 
    }

    function _maximumLockedValueOfCollection(CollectionConfiguration memory collection, uint256 liquidity) internal pure returns (uint256){
        return liquidity.mulDiv(collection.weight, GENERAL_UNIT, Math.Rounding.Down);
    }

    function _maximumLockedValue(uint256 liquidity) internal pure returns (uint256) {
        return liquidity.mulDiv(MAXIMUM_LOCK_RATIO, GENERAL_UNIT, Math.Rounding.Down);
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
        CollectionConfiguration memory config = _collections[collection];
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
        premium = pricer.getPremium(optionType, strike_.spotPrice, strike_.strikePrice, adjustedVol, strike_.duration);
    }

    function _estimatePremium(address collection, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) internal view 
        returns(uint256 premium, Strike memory strike_)
    {
        if(amount == 0){
            revert ZeroAmount(address(this));
        }
        CollectionConfiguration memory config = _collections[collection];
        strike_.spotPrice = IOracle(_oracle).getAssetPrice(collection);
        strike_.strikePrice = strikePrice;
        strike_.expiry = expiry;
        strike_.duration = expiry - block.timestamp;
        _validateOpenOption1(amount, optionType, strike_);
        premium = _calculateStrikeAndPremium(collection, optionType, strike_).mulDiv(amount, UNIT, Math.Rounding.Up);
        _validateOpenOption2(config, strike_.spotPrice.mulDiv(amount, UNIT, Math.Rounding.Up), premium);
        return (premium, strike_);
    }

    function estimatePremium(address collection, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) public view override 
        returns(uint256 premium)
    {
        (premium, ) = _estimatePremium(collection, optionType, strikePrice, expiry, amount);
        return premium;
    }

    //for options
    function openPosition(address collection, address onBehalfOf, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount, uint256 maximumPremium) 
        public override onlyUnpaused
        returns(uint256 positionId, uint256 premium)
    {
        if(_collections[collection].frozen){
            revert FrozenMarket(address(this), collection);
        }
        if(!_collections[collection].activated){
            revert DeactivatedMarket(address(this), collection);
        }
        Strike memory strike_;
        (premium, strike_) = _estimatePremium(collection, optionType, strikePrice, expiry, amount);
        uint256 strikeId = _nextId++;
        _strikes[strikeId] = strike_;
        emit CreateStrike(strikeId, strike_.duration, strike_.expiry, strike_.spotPrice, strike_.strikePrice);
        //mint option token
        OptionToken optionToken = OptionToken( _collections[collection].optionToken);
        positionId = optionToken.openPosition(_msgSender(), onBehalfOf, optionType, strikeId, amount, maximumPremium);
        _totalLockedAssets += optionToken.lockedValue(positionId);
        emit OpenPosition(collection, strikeId, positionId, premium);
        emit ReceivePremiumAndFee(_msgSender(), maximumPremium, KEEPER_FEE);
        IERC20(_asset).safeTransferFrom(_msgSender(), address(this), maximumPremium + KEEPER_FEE);
        return (positionId, premium);
    }

    function activePosition(address collection, uint256 positionId) public override onlyKeeper onlyUnpaused returns(uint256 premium){
        if(_collections[collection].frozen){
            revert FrozenMarket(address(this), collection);
        }
        if(!_collections[collection].activated){
            revert DeactivatedMarket(address(this), collection);
        }
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
        premium = _calculateStrikeAndPremium(collection, position.optionType, strike_).mulDiv(position.amount, UNIT, Math.Rounding.Up);
        if(premium > position.maximumPremium){
            _closePendingPosition(collection, positionId);
        }
        else{
            _unrealizedPremium += premium;
            optionToken.activePosition(positionId, premium);
            //transfer premium from the caller to the vault
            uint256 amountToReserve = premium.mulDiv(RESERVE_RATIO, GENERAL_UNIT, Math.Rounding.Up);
            _strikes[position.strikeId] = strike_;
            address payer = position.payer;
            emit ReceivePremium(payer, amountToReserve, premium - amountToReserve);
            emit ReceiveKeeperFee(payer, KEEPER_FEE);
            emit ReturnExcessPremium(payer, position.maximumPremium - premium);
            IERC20(_asset).safeTransfer(_reserve, amountToReserve + KEEPER_FEE);
            IERC20(_asset).safeTransfer(_lpToken, premium - amountToReserve);
            IERC20(_asset).safeTransfer(payer, position.maximumPremium - premium);
        }
    }

    function closePosition(address collection, uint256 positionId) public override onlyKeeper onlyUnpaused returns(uint256 profit){
        //calculate fee
        //burn callOption token
        //transfer revenue from the vault to caller
        if(_collections[collection].frozen){
            revert FrozenMarket(address(this), collection);
        }
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
        address to = optionToken.ownerOf(positionId);
        optionToken.closePosition(positionId);
        delete _strikes[position.strikeId];
        emit DestoryStrike(position.strikeId);
        uint256 fee;
        (profit, fee) = _calculateExerciseProfit(position.optionType, currentPrice, strike_.strikePrice, position.amount);
        if(profit != 0){
            _realizedPNL -= int256(profit + fee);
            IERC20(_asset).safeTransferFrom(_lpToken, _backstopPool, fee);
            IERC20(_asset).safeTransferFrom(_lpToken, to, profit);
            emit SendRevenue(to, profit, fee);
        }
        uint256 price = LPToken(_lpToken).convertToAssets(HIGH_PRECISION_UNIT);
        emit UpdateLPTokenPrice(_lpToken, price);
        return profit;
    }

    function _closePendingPosition(address collection, uint256 positionId) internal {
        OptionToken optionToken = OptionToken(_collections[collection].optionToken);
        _totalLockedAssets -= optionToken.lockedValue(positionId);
        OptionPosition memory position = optionToken.optionPosition(positionId);
        uint256 strikeId = position.strikeId;
        delete _strikes[strikeId];
        emit DestoryStrike(strikeId);
        address payer = position.payer;
        uint256 premium = position.maximumPremium;
        optionToken.forceClosePendingPosition(positionId);
        emit ReturnExcessPremium(payer, premium);
        IERC20(_asset).safeTransferFrom(address(this), payer, premium);
    }

    function forceClosePendingPosition(address collection, uint256 positionId) public override onlyUnpaused {
        if(_collections[collection].frozen){
            revert FrozenMarket(address(this), collection);
        }
        _closePendingPosition(collection, positionId);
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
        uint256 fee = currentPrice.mulDiv(amount, UNIT, Math.Rounding.Down).mulDiv(FEE_RATIO, GENERAL_UNIT, Math.Rounding.Up);
        uint256 maximumFee = profit.mulDiv(PROFIT_FEE_RATIO, GENERAL_UNIT, Math.Rounding.Up);
        fee = Math.min(fee, maximumFee);
        return (profit - fee, fee);
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