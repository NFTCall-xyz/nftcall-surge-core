// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC721Metadata, ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {DECIMALS, UNIT} from "../libraries/DataTypes.sol";

import {IVault} from "../interfaces/IVault.sol";
import {SimpleInitializable} from "../libraries/SimpleInitializable.sol";

import "../interfaces/IOptionToken.sol";

contract OptionToken is IOptionToken, ERC721Enumerable, Ownable, SimpleInitializable {
    using Strings for uint256;
    using Math for uint256;

    address public immutable collection;
    address private _vault;
    uint256 internal constant _decimals = DECIMALS;
    uint256 private _totalValue;
    uint256 private _totalAmount;
    uint256 private _nextId = 1;
    string private _baseTokenURI;

    mapping(uint256 => OptionPosition) internal _options;
    mapping(OptionType => uint256) private _totalAmounts;
    mapping(OptionType => uint256) private _totalValues;

    modifier onlyVault() {
        if (_msgSender() != _vault) {
            revert OnlyVault(address(this), _msgSender(), _vault);
        }
        _;
    }

    constructor(address collectionAddress, string memory name_, string memory symbol_, string memory baseURI)
        ERC721(name_, symbol_) Ownable()
    {
        collection = collectionAddress;
        _baseTokenURI = baseURI;
    }

    function initialize(address vaultAddress) public onlyOwner initializer {
        if(vaultAddress == address(0)){
            revert ZeroVaultAddress(address(this));
        }
        _vault = vaultAddress;
        emit Initialize(vaultAddress);
    }

    function vault() public view override returns(address) {
        return _vault;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) 
    {
        string memory baseURI = _baseTokenURI;
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function setBaseURI(string memory baseURI) public override onlyOwner {
        _baseTokenURI = baseURI;
        emit UpdateBaseURI(baseURI);
    }

    function openPosition(address payer, address to, OptionType optionType, uint256 strikeId, uint256 amount, uint256 maximumPremium) public override onlyVault returns(uint256)
    {
        if(amount == 0) {
            revert ZeroAmount(address(this));
        }
        uint256 positionId = _nextId++;
        _options[positionId] = OptionPosition(PositionState.PENDING, optionType, payer, strikeId, amount, 0, maximumPremium);
        _totalValue += lockedValue(positionId);
        emit OpenPosition(payer, to, positionId, optionType, strikeId, amount, maximumPremium);
        _safeMint(to, positionId);
        return positionId;
    }

    function activePosition(uint256 positionId, uint256 premium) public override onlyVault
    {
        OptionPosition memory po = _options[positionId];
        if(po.state != PositionState.PENDING) {
            revert IsNotPending(address(this), positionId, po.state);
        }
        po.state = PositionState.ACTIVE;
        po.premium = premium;
        _totalAmount += po.amount;
        _totalAmounts[po.optionType] += po.amount;
        _totalValues[po.optionType] += lockedValue(positionId);
        _options[positionId] = po;
        emit ActivePosition(positionId, premium);
    }

    function closePosition(uint256 positionId) public override onlyVault
    {
        if(_options[positionId].state != PositionState.ACTIVE) {
            revert IsNotActive(address(this), positionId, _options[positionId].state);
        }
        OptionPosition memory po = _options[positionId];
        _totalAmount -= po.amount;
        _totalAmounts[po.optionType] -= po.amount;
        _totalValues[po.optionType] -= lockedValue(positionId);        
        _closePosition(positionId);
        emit ClosePosition(positionId);
    }

    function forceClosePendingPosition(uint256 positionId) public override onlyVault
    {
        if(_options[positionId].state != PositionState.PENDING) {
            revert IsNotPending(address(this), positionId, _options[positionId].state);
        }
        _closePosition(positionId);
        emit ForceClosePosition(positionId);
    }

    function _closePosition(uint256 positionId) internal {
        _totalValue -= lockedValue(positionId);
        delete _options[positionId];
        _burn(positionId);
    }

    function totalAmount() public override view returns(uint256) {
        return _totalAmount;
    }

    function totalAmount(OptionType optionType) public override view returns(uint256) {
        return _totalAmounts[optionType];
    }

    function totalValue() public override view returns(uint256) 
    {
        return(_totalValue);
    }

    function totalValue(OptionType optionType) public override view returns(uint256) {
        return _totalValues[optionType];
    }

    function lockedValue(uint256 positionId) public view override returns(uint256) {
        OptionPosition memory position = _options[positionId];
        if(position.state == PositionState.EMPTY) {
            revert NonexistentPosition(address(this), positionId);
        }
        if(position.optionType == OptionType.LONG_CALL) {
            return IVault(_vault).strike(position.strikeId).entryPrice.mulDiv(position.amount, UNIT, Math.Rounding.Up);
        } else {
            return IVault(_vault).strike(position.strikeId).strikePrice.mulDiv(position.amount, UNIT, Math.Rounding.Up);
        }
    }

    function optionPosition(uint256 positionId) public view override returns(OptionPosition memory position) {
        position = _options[positionId];
        if(position.state == PositionState.EMPTY) {
            revert NonexistentPosition(address(this), positionId);
        }
        return position;
    }

    function optionPositionState(uint256 positionId) public view override returns(PositionState state) {
        state = _options[positionId].state;
        if(state == PositionState.EMPTY){
            revert NonexistentPosition(address(this), positionId);
        }
        return state;
    }
}