// SPDX-License-Identifier: ISC
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LyraMath} from "../libraries/LyraMath.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {GENERAL_UNIT, DECIMALS, UNIT, HIGH_PRECISION_UNIT} from "../libraries/DataTypes.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {OptionType, OptionPosition, PositionState, IOptionToken} from "../interfaces/IOptionToken.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPremium, PremiumVars} from "../interfaces/IPremium.sol";
import {IPricer} from "../interfaces/IPricer.sol";
import {IAssetRiskCache} from "../interfaces/IAssetRiskCache.sol";
import {OptionToken} from "../tokens/OptionToken.sol";

import "../interfaces/IVault.sol";

import "hardhat/console.sol";

contract Vault is IVault, Pausable, Ownable{
    using StorageSlot for bytes32;
    using Math for uint256;
    using LyraMath for int256;
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
    uint256 private _nextId = 1;
    mapping(address => CollectionConfiguration) private _collections;
    mapping(uint256 => address) private _collectionsList;
    mapping(uint256 => Strike) private _strikes;

    uint256 private _collectionsCount;
    uint256 private _totalLockedAssets;
    int256 private _realizedPNL;
    uint256 private _unrealizedPremium;
    int256 private _unrealizedPNL;
    uint256 private _minimumAnnualRateOfReturnOnLockedAssets = UNIT * 5 / 100; // 5%
    uint256 private _timeWindowForActivation = 1 hours;

    
    uint256 private FEE_RATIO =  GENERAL_UNIT * 5 / 1000; // 0.5%
    uint256 private PROFIT_FEE_RATIO = GENERAL_UNIT * 125 / 1000; // 12.5%

    uint8 private constant _decimals = uint8(DECIMALS);
    uint256 private constant _SECONDS_PRE_YEAR = 365 * 24 * 3600;
    

    uint256 public override constant RESERVE_RATIO = GENERAL_UNIT * 10 / 100; // 10%
    uint256 public override constant MAXIMUM_LOCK_RATIO = GENERAL_UNIT * 95 / 100; // 95%

    uint256 private _maximumCallStrikePriceRatio = GENERAL_UNIT * 210 / 100; // 210%
    uint256 private _minimumCallStrikePriceRatio = GENERAL_UNIT * 110 / 100; // 110%
    uint256 private _maximumPutStrikePriceRatio = GENERAL_UNIT * 90 / 100; // 90%
    uint256 private _minimumPutStrikePriceRatie = GENERAL_UNIT * 50 / 100; // 50%
    uint256 public override constant KEEPER_FEE = 5 * 10**13; // 0.00005 ETH
    uint256 public override constant TIME_SCALE = 24 * 3;

    uint256 private _minimumDuration = 3 days / TIME_SCALE;
    uint256 private _maximumDuration = 30 days / TIME_SCALE;

    constructor (address asset, address lpToken, address oracle, address pricer, address riskCache, address reserve_, address backstopPool_)
        Ownable()
    {
        if(asset == address(0)){
            revert ZeroAddress(_msgSender());
        }
        if(lpToken == address(0)){
            revert ZeroAddress(_msgSender());
        }
        if(oracle == address(0)){
            revert ZeroAddress(_msgSender());
        }
        if(pricer == address(0)){
            revert ZeroAddress(_msgSender());
        }
        if(riskCache == address(0)){
            revert ZeroAddress(_msgSender());
        }
        if(reserve_ == address(0)){
            revert ZeroAddress(_msgSender());
        }
        if(backstopPool_ == address(0)){
            revert ZeroAddress(_msgSender());
        }

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
        if (_msgSender() != _keeper) {
            revert OnlyKeeper(address(this), _msgSender(), _keeper);
        }
        _;
    }

    modifier onlyUnpaused() {
        if (_paused) {
            revert OnlyUnpaused(address(this), _msgSender());
        }
        _;
    }

    function decimals() public override view returns(uint8) {
        return _decimals;
    }

    function keeper() public override view returns(address) {
        return _keeper;
    }

    function setKeeper(address keeperAddress) public override onlyOwner {
        if(keeperAddress == address(0)){
            revert ZeroAddress(address(this));
        }
        _keeper = keeperAddress;
        emit UpdateKeeper(_msgSender(), keeperAddress);
    }

    function reserve() public override view returns(address) {
        return _reserve;
    }

    function backstopPool() public override view returns(address) {
        return _backstopPool;
    }

    function pause() public override onlyOwner {
        _paused = true;
        emit Paused(_msgSender());
    }

    function unpause() public override onlyOwner {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    function isPaused() public override view returns(bool) {
        return _paused;
    }

    function activateMarket(address collection) public override onlyOwner {
        _collections[collection].activated = true;
        emit ActivateMarket(_msgSender(), collection);
    }

    function deactivateMarket(address collection) public override onlyOwner {
        _collections[collection].activated = false;
        emit DeactivateMarket(_msgSender(), collection);
    }

    function isActiveMarket(address collection) public override view returns(bool) {
        return _collections[collection].activated;
    }

    function freezeMarket(address collection) public override onlyOwner {
        _collections[collection].frozen = true;
        emit FreezeMarket(_msgSender(), collection);
    }

    function defreezeMarket(address collection) public override onlyOwner {
        _collections[collection].frozen = false;
        emit DefreezeMarket(_msgSender(), collection);
    }

    function isFrozenMarket(address collection) public override view returns(bool) {
        return _collections[collection].frozen;
    }

    function unrealizedPNL() public override view returns(int256) {
        return _unrealizedPNL;
    }

    function updateCollectionRisk(address collection, int256 delta, int256 PNL) public override onlyKeeper{
        IAssetRiskCache(_riskCache).updateAssetRisk(collection, delta, PNL);
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

    function minimumAnnualRateOfReturnOnLockedAssets() public override view returns(uint256) {
        return _minimumAnnualRateOfReturnOnLockedAssets;
    }

    function setMinimumAnnualRateOfReturnOnLockedAssets(uint256 ratio) public override onlyOwner {
        _minimumAnnualRateOfReturnOnLockedAssets = ratio;
        emit UpdateMinimumAnnualRateOfReturnOnLockedAssets(_msgSender(), ratio);
    }

    function timeWindowForActivation() public override view returns(uint256) {
        return _timeWindowForActivation;
    }

    function setTimeWindowForActivation(uint256 timeWindows) public override onlyOwner {
        _timeWindowForActivation = timeWindows;
        emit UpdateTimeWindowForActivation(_msgSender(), timeWindows);
    }

    function feeRatio() public override view returns(uint256) {
        return FEE_RATIO;
    }

    function profitFeeRatio() public override view returns(uint256) {
        return PROFIT_FEE_RATIO;
    }

    function MAXIMUM_CALL_STRIKE_PRICE_RATIO() public override view returns(uint256) {
        return _maximumCallStrikePriceRatio;
    }

    function MINIMUM_CALL_STRIKE_PRICE_RATIO() public override view returns(uint256) {
        return _minimumCallStrikePriceRatio;
    }

    function MAXIMUM_PUT_STRIKE_PRICE_RATIO() public override view returns(uint256) {
        return _maximumPutStrikePriceRatio;
    }

    function MINIMUM_PUT_STRIKE_PRICE_RATIO() public override view returns(uint256) {
        return _minimumPutStrikePriceRatie;
    }

    function MINIMUM_DURATION() public override view returns(uint256) {
        return _minimumDuration;
    }

    function MAXIMUM_DURATION() public override view returns(uint256) {
        return _maximumDuration;
    }

    function setCallStrikePriceRatioRange(uint256 minimumRatio, uint256 maximumRatio) public override onlyOwner{
        if(minimumRatio <= GENERAL_UNIT || minimumRatio >= maximumRatio){
            revert InvalidCallStrikePriceRatioRange(address(this), minimumRatio, maximumRatio);
        }
        _minimumCallStrikePriceRatio = minimumRatio;
        _maximumCallStrikePriceRatio = maximumRatio;
        emit UpdateCallStrikePriceRatioRange(_msgSender(), minimumRatio, maximumRatio);
    }

    function setPutStrikePriceRatioRange(uint256 minimumRatio, uint256 maximumRatio) public override onlyOwner{
        if(maximumRatio >= GENERAL_UNIT || minimumRatio >= maximumRatio){
            revert InvalidPutStrikePriceRatioRange(address(this), minimumRatio, maximumRatio);
        }
        _minimumPutStrikePriceRatie = minimumRatio;
        _maximumPutStrikePriceRatio = maximumRatio;
        emit UpdatePutStrikePriceRatioRange(_msgSender(), minimumRatio, maximumRatio);
    }

    function setDurationRange(uint256 minimumDuration, uint256 maximumDuration) public override onlyOwner{
        if(minimumDuration == 0 || minimumDuration >= maximumDuration){
            revert InvalidDurationRange(address(this), minimumDuration, maximumDuration);
        }
        _minimumDuration = minimumDuration / TIME_SCALE;
        _maximumDuration = maximumDuration / TIME_SCALE;
        emit UpdateDurationRange(_msgSender(), minimumDuration, maximumDuration);
    }

    function deposit(uint256 amount, address onBehalfOf) public override onlyUnpaused{
        LPToken(_lpToken).deposit(amount, _msgSender(), onBehalfOf);
    }

    function withdraw(uint256 amount, address to) public override onlyUnpaused returns(uint256){
        return LPToken(_lpToken).withdraw(amount, to, _msgSender());
    }

    function redeem(uint256 amount, address to) public override onlyUnpaused returns(uint256){
        return LPToken(_lpToken).redeem(amount, to, _msgSender());
    }

    function totalAssets() public view override returns(uint256) {
        return LPToken(_lpToken).totalAssets();
    }

    function totalLockedAssets() public view override returns(uint256) {
        return _totalLockedAssets;
    }

    function _assetReturn(uint256 amount, uint256 duration, uint256 annualRate) internal pure returns(uint256) {
        return amount.mulDiv(annualRate, UNIT, Math.Rounding.Up).mulDiv(duration, _SECONDS_PRE_YEAR, Math.Rounding.Up);
    }

    function minimumPremium(address collection, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) public view override returns(uint256) {
        uint256 entryPrice = IOracle(_oracle).getAssetPrice(collection);
        uint256 duration = expiry - block.timestamp;
        uint256 lockedValue = _lockedValue(optionType, entryPrice, strikePrice, amount);
        return _assetReturn(lockedValue, duration, _minimumAnnualRateOfReturnOnLockedAssets);
    }

    function _validateOpenOption1(uint256 amount, OptionType optionType, Strike memory strike_) internal view{
        if(amount == 0){
            revert ZeroAmount(address(this));
        }
        if(optionType == OptionType.LONG_CALL){
            if(strike_.strikePrice > strike_.entryPrice.mulDiv(_maximumCallStrikePriceRatio, GENERAL_UNIT, Math.Rounding.Down) 
               || strike_.strikePrice < strike_.entryPrice.mulDiv(_minimumCallStrikePriceRatio, GENERAL_UNIT, Math.Rounding.Up)){
                revert InvalidStrikePrice(address(this), strike_.strikePrice, strike_.entryPrice);
            }
        } else {
            if(strike_.strikePrice > strike_.entryPrice.mulDiv(_maximumPutStrikePriceRatio, GENERAL_UNIT, Math.Rounding.Down) 
               || strike_.strikePrice < strike_.entryPrice.mulDiv(_minimumPutStrikePriceRatie, GENERAL_UNIT, Math.Rounding.Up)){
                revert InvalidStrikePrice(address(this), strike_.strikePrice, strike_.entryPrice);
            }
        }
        if(strike_.duration > _maximumDuration || strike_.duration < _minimumDuration) {
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
        uint256 currentAmount = LPToken(_lpToken).totalAssets() + premium;
        uint256 totalLockedValue = OptionToken(collection.optionToken).totalValue();
        if(totalLockedValue + valueToBeLocked > _maximumLockedValueOfCollection(collection, currentAmount)){
            revert InsufficientLiquidityForCollection(address(this), OptionToken(collection.optionToken).collection(), totalLockedValue, valueToBeLocked, currentAmount);
        }
        if(_totalLockedAssets + valueToBeLocked > _maximumLockedValue(currentAmount)){
            revert InsufficientLiquidity(address(this), _totalLockedAssets, valueToBeLocked, currentAmount);
        }
    }

    function _lockedValue(OptionType optionType, uint256 entryPrice, uint256 strikePrice, uint256 amount) internal pure returns(uint256 lockedValue) {
        if(optionType == OptionType.LONG_CALL){
            lockedValue = entryPrice.mulDiv(amount, UNIT, Math.Rounding.Up);
        }
        else {
            lockedValue = strikePrice.mulDiv(amount, UNIT, Math.Rounding.Up);
        }
    }

    function maximumOptionAmount(address collection, OptionType optionType) external view override returns(uint256 amount) {
        CollectionConfiguration memory config = _collections[collection];
        uint256 currentAmount = LPToken(_lpToken).totalAssets();
        uint256 totalLockedValue = OptionToken(config.optionToken).totalValue();
        uint256 maximumLockedValueOfCollection = _maximumLockedValueOfCollection(config, currentAmount);
        if(totalLockedValue >= maximumLockedValueOfCollection){
            return 0;
        }
        uint256 maximumLockedValue = _maximumLockedValue(currentAmount);
        if(_totalLockedAssets >= maximumLockedValue){
            return 0;
        }
        uint256 entryPrice = IOracle(_oracle).getAssetPrice(collection);
        uint256 maximumOptionValue = Math.min(maximumLockedValueOfCollection - totalLockedValue, maximumLockedValue - _totalLockedAssets);
        amount = maximumOptionValue.mulDiv(UNIT, entryPrice, Math.Rounding.Down);
    }

    function strike(uint256 strikeId) public view override returns(Strike memory s){
        s = _strikes[strikeId];
        if(s.strikePrice == 0){
            revert InvalidStrikeId(address(this), strikeId);
        }
    }

    function _adjustedPremium(address collection, OptionType optionType, Strike memory strike_, uint256 amount) internal view returns(uint256 premium){
        IPricer pricer = IPricer(_pricer);
        uint256 lockedValue = _lockedValue(optionType, strike_.entryPrice, strike_.strikePrice, amount);
        uint256 adjustedVol = pricer.getAdjustedVol(collection, optionType, strike_.strikePrice, lockedValue);
        (uint256 call, uint256 put) = pricer.optionPrices(strike_.entryPrice, strike_.strikePrice, adjustedVol, strike_.duration * TIME_SCALE);
        if(optionType == OptionType.LONG_CALL){
            premium = call;
            (uint256 buybackPremium, ) = pricer.optionPrices(strike_.entryPrice, strike_.strikePrice + strike_.entryPrice, adjustedVol, strike_.duration * TIME_SCALE);
            premium = premium - buybackPremium;
        } 
        else {
            premium = put;
        }
    }

    function _premiumAndDelta(address collection, OptionType optionType, uint256 entryPrice, uint256 strikePrice, uint256 duration) internal view returns(uint256 premium, int256 delta){
        IPricer pricer = IPricer(_pricer);
        (uint256 spotPrice, uint vol) = IOracle(_oracle).getAssetPriceAndVol(collection);
        (premium, delta,,) = pricer.getPremiumDeltaStdVega(optionType, spotPrice, strikePrice, vol, duration * TIME_SCALE);
        if(optionType == OptionType.LONG_CALL){
            (uint256 buybackPremium, int256 buybackDelta, ,) = pricer.getPremiumDeltaStdVega(OptionType.LONG_CALL, spotPrice, strikePrice + entryPrice, vol, duration * TIME_SCALE);
            premium = premium - buybackPremium;
            delta = delta - buybackDelta;
        }
    }

    function _estimatePremium(address collection, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) internal view 
        returns(uint256 premium, Strike memory strike_)
    {
        if(amount == 0){
            revert ZeroAmount(address(this));
        }
        CollectionConfiguration memory config = _collections[collection];
        strike_.entryPrice = IOracle(_oracle).getAssetPrice(collection);
        strike_.strikePrice = strikePrice;
        // strike_.expiry = expiry;
        strike_.duration = (expiry - block.timestamp) / TIME_SCALE;
        strike_.expiry = block.timestamp + strike_.duration;
        _validateOpenOption1(amount, optionType, strike_);
        premium = _adjustedPremium(collection, optionType, strike_, amount);
        premium = premium.mulDiv(amount, UNIT, Math.Rounding.Up);
        _validateOpenOption2(config, strike_.entryPrice.mulDiv(amount, UNIT, Math.Rounding.Up), premium);
        return (premium, strike_);
    }

    function estimatePremium(address collection, OptionType optionType, uint256 strikePrice, uint256 expiry, uint256 amount) public view override 
        returns(uint256 premium)
    {
        Strike memory strike_;
        (premium, strike_) = _estimatePremium(collection, optionType, strikePrice, expiry, amount);
        uint256 minimumPremium_ = _assetReturn(
            _lockedValue(optionType, strike_.entryPrice, strike_.strikePrice, amount),
            strike_.duration, 
            _minimumAnnualRateOfReturnOnLockedAssets);
        return Math.max(premium, minimumPremium_);
    }

    function adjustedVolatility(address collection, OptionType optionType, uint256 strikePrice, uint256 amount) public view override returns(uint256 adjustedVol){
        IPricer pricer = IPricer(_pricer);
        uint256 entryPrice = IOracle(_oracle).getAssetPrice(collection);
        uint256 lockedValue = _lockedValue(optionType, entryPrice, strikePrice, amount);
        return pricer.getAdjustedVol(collection, optionType, strikePrice, lockedValue);
    }

    struct OpenPositionLocalVars {
        OptionToken optionToken;
        Strike strike;
        address caller;
        uint256 strikeId;
        uint256 lockedValue;
        uint256 minimumPremium;
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
        OpenPositionLocalVars memory vars;
        (premium, vars.strike) = _estimatePremium(collection, optionType, strikePrice, expiry, amount);
        vars.strikeId = _nextId++;
        _strikes[vars.strikeId] = vars.strike;
        emit CreateStrike(vars.strikeId, vars.strike.duration, vars.strike.expiry, vars.strike.entryPrice, vars.strike.strikePrice);
        vars.lockedValue = _lockedValue(optionType, vars.strike.entryPrice, vars.strike.strikePrice, amount);
        vars.minimumPremium = _assetReturn(vars.lockedValue, vars.strike.duration, _minimumAnnualRateOfReturnOnLockedAssets);
        premium = Math.max(premium, vars.minimumPremium);

        //mint option token
        vars.optionToken = OptionToken( _collections[collection].optionToken);
        _totalLockedAssets += vars.lockedValue;
        OpenPositionEventParameters memory eventParameters = OpenPositionEventParameters(
            optionType,
            vars.strike.expiry,
            vars.strike.entryPrice,
            vars.strike.strikePrice,
            amount,
            premium,
            KEEPER_FEE
        );
        vars.caller = _msgSender();
        positionId = vars.optionToken.openPosition(vars.caller, onBehalfOf, optionType, vars.strikeId, amount, maximumPremium);
        emit OpenPosition(vars.caller, onBehalfOf, collection, positionId, eventParameters);
        IERC20(_asset).safeTransferFrom(vars.caller, address(this), maximumPremium + KEEPER_FEE);
        return (positionId, premium);
    }

    struct ActivatePositionLocalVars {
        OptionToken optionToken;
        OptionPosition position;
        Strike strike;
        uint256 excessPremium;
        uint256 unadjustedPremium;
        int256 collectionDelta;
        int256 collectionPNL;
        uint256 amountToReserve;
    }

    function activatePosition(address collection, uint256 positionId) public override onlyKeeper onlyUnpaused returns(uint256 premium, int256 delta){
        if(_collections[collection].frozen){
            revert FrozenMarket(address(this), collection);
        }
        if(!_collections[collection].activated){
            revert DeactivatedMarket(address(this), collection);
        }
        ActivatePositionLocalVars memory vars;
        vars.optionToken = OptionToken(_collections[collection].optionToken);
        vars.position = vars.optionToken.optionPosition(positionId);
        vars.strike = _strikes[vars.position.strikeId];
        if(block.timestamp + vars.strike.duration - vars.strike.expiry > _timeWindowForActivation){
            emit FailPosition(vars.optionToken.ownerOf(positionId), collection, positionId, vars.position.premium, FailureReason.EXPIRED);
            _closePendingPosition(collection, positionId);
            return (0, 0);
        }
        vars.strike.duration = vars.strike.expiry - block.timestamp;
        vars.strike.entryPrice = IOracle(_oracle).getAssetPrice(collection);
        premium = _adjustedPremium(collection, vars.position.optionType, vars.strike, vars.position.amount);
        premium = premium.mulDiv(vars.position.amount, UNIT, Math.Rounding.Up);
        if(premium > vars.position.maximumPremium){
            emit FailPosition(vars.optionToken.ownerOf(positionId), collection, positionId, vars.position.maximumPremium, FailureReason.PREMIUM_TOO_HIGH);
            _closePendingPosition(collection, positionId);
        }
        else{
            uint256 minimumPremium_ = _assetReturn(
                _lockedValue(vars.position.optionType, vars.strike.entryPrice, vars.strike.strikePrice, vars.position.amount),
                vars.strike.duration, 
                _minimumAnnualRateOfReturnOnLockedAssets);
            premium = Math.max(premium, minimumPremium_);
            _unrealizedPremium += premium;
            (vars.unadjustedPremium, delta) = _premiumAndDelta(collection, vars.position.optionType, vars.strike.entryPrice, vars.strike.strikePrice, vars.strike.duration);
            (vars.collectionDelta, vars.collectionPNL) = IAssetRiskCache(_riskCache).getAssetRisk(collection);
            vars.collectionDelta = vars.collectionDelta.iMulDiv(int256(vars.optionToken.totalAmount()), UNIT, Math.Rounding.Down);
            vars.collectionDelta -= delta.iMulDiv(int256(vars.position.amount), UNIT, Math.Rounding.Down);
            vars.collectionPNL += int256(premium) - int256(vars.unadjustedPremium.mulDiv(vars.position.amount, UNIT, Math.Rounding.Down));
            //transfer premium from the caller to the vault
            vars.amountToReserve = premium.mulDiv(RESERVE_RATIO, GENERAL_UNIT, Math.Rounding.Up);
            _strikes[vars.position.strikeId] = vars.strike;
            vars.excessPremium = vars.position.maximumPremium - premium;
            LPToken(_lpToken).increaseTotalAssets(premium - vars.amountToReserve);
            _activatePosition(collection, vars.optionToken, positionId, premium, vars.excessPremium, delta);
            vars.collectionDelta = vars.collectionDelta.iMulDiv(int256(UNIT), vars.optionToken.totalAmount(), Math.Rounding.Down);
            IAssetRiskCache(_riskCache).updateAssetRisk(collection, vars.collectionDelta, vars.collectionPNL);
            IERC20(_asset).safeTransfer(_reserve, vars.amountToReserve + KEEPER_FEE);
            IERC20(_asset).safeTransfer(_lpToken, premium - vars.amountToReserve);
            if(vars.excessPremium > 0){
                IERC20(_asset).safeTransfer(vars.position.payer, vars.excessPremium);
            }
            uint256 price = LPToken(_lpToken).convertToAssets(HIGH_PRECISION_UNIT);
            emit UpdateLPTokenPrice(_lpToken, price);
        }
    }

    function _activatePosition(address collection, OptionToken optionToken, uint256 positionId, uint256 premium, uint256 excessPremium, int256 delta) internal{
            emit ActivatePosition(optionToken.ownerOf(positionId), collection, positionId, premium, excessPremium, delta);
            optionToken.activePosition(positionId, premium);
            
    }


    function positionPNLWeightedDelta(address collection, uint256 positionId) public view override returns(int256 unrealizePNL, int256 weightedDelta) {
        OptionToken optionToken = OptionToken(_collections[collection].optionToken);
        OptionPosition memory position = optionToken.optionPosition(positionId);
        Strike memory strike_ = _strikes[position.strikeId];
        uint256 premium;
        (premium, weightedDelta) = _premiumAndDelta(collection, position.optionType, strike_.entryPrice, strike_.strikePrice, strike_.expiry - block.timestamp);
        unrealizePNL = int256(premium.mulDiv(position.amount, UNIT, Math.Rounding.Up)) - int256(position.premium);
        weightedDelta = weightedDelta.iMulDiv(int256(position.amount), UNIT, Math.Rounding.Up);
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

        uint256 settlementPrice = IOracle(_oracle).getAssetPrice(collection);
        address to = optionToken.ownerOf(positionId);
        optionToken.closePosition(positionId);
        delete _strikes[position.strikeId];
        emit DestoryStrike(position.strikeId);
        uint256 fee;
        (profit, fee) = _calculateExerciseProfit(position.optionType, settlementPrice, strike_.entryPrice, strike_.strikePrice, position.amount);
        if(profit != 0){
            _realizedPNL -= int256(profit + fee);
            LPToken(_lpToken).decreaseTotalAssets(profit + fee);
            emit ExercisePosition(to, collection, positionId, profit, fee, settlementPrice);
            IERC20(_asset).safeTransferFrom(_lpToken, _backstopPool, fee);
            IERC20(_asset).safeTransferFrom(_lpToken, to, profit);
        }
        else{
            emit ExpirePosition(to, collection, positionId, settlementPrice);
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
        address payer = position.payer;
        uint256 premium = position.maximumPremium;
        optionToken.forceClosePendingPosition(positionId);
        delete _strikes[strikeId];
        emit DestoryStrike(strikeId);
        IERC20(_asset).safeTransfer(payer, premium);
        IERC20(_asset).safeTransfer(_reserve, KEEPER_FEE);
    }

    function forceClosePendingPosition(address collection, uint256 positionId) public override onlyUnpaused {
        if(_collections[collection].frozen){
            revert FrozenMarket(address(this), collection);
        }
        address caller = _msgSender();
        OptionToken optionToken = OptionToken(_collections[collection].optionToken);
        address owner =  optionToken.ownerOf(positionId);
        address payer = optionToken.optionPosition(positionId).payer;
        if(caller != _keeper && caller != owner && caller != payer){
            revert OnlyKeeperOrOwnerOrPayer(address(this), caller, _keeper, owner, payer);
        }
        emit CancelPosition(owner, collection, positionId, optionToken.optionPosition(positionId).maximumPremium);
        _closePendingPosition(collection, positionId);
    }

    function _calculateExerciseProfit(OptionType optionType, uint256 settlementPrice, uint256 entryPrice, uint256 strikePrice, uint256 amount) internal view returns(uint256, uint256){
        uint256 profit;
        if(optionType == OptionType.LONG_CALL){
            if(settlementPrice <= strikePrice){
                return (0, 0);
            }
            profit = settlementPrice - strikePrice;
            if(profit > entryPrice){
                profit = entryPrice;
            }
            profit = profit.mulDiv(amount, UNIT, Math.Rounding.Down);
        }
        else{
            if(settlementPrice >= strikePrice) {
                return (0, 0);
            }
            profit = (strikePrice - settlementPrice).mulDiv(amount, UNIT, Math.Rounding.Down);
        }
        uint256 fee = settlementPrice.mulDiv(amount, UNIT, Math.Rounding.Down).mulDiv(FEE_RATIO, GENERAL_UNIT, Math.Rounding.Up);
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

    function collectUntitledAssetsFromLPToken(address receiver) public onlyOwner returns(uint256 amount) {
        amount = LPToken(_lpToken).collectUntitledAssets(receiver);
    }

    function sendAssetsToLPToken(uint256 amount) public onlyOwner {
        emit SendAssetsToLPToken(_msgSender(), amount);
        IERC20(_asset).safeTransferFrom(_msgSender(), _lpToken, amount);
        LPToken(_lpToken).increaseTotalAssets(amount);
    }
}