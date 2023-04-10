// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC721Metadata, ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVault} from "../interfaces/IVault.sol";
import {OptionType, PositionState, OptionPosition, IOptionBase} from "../interfaces/IOptionBase.sol";
import {SimpleInitializable} from "../libraries/SimpleInitializable.sol";

abstract contract OptionBase is IOptionBase, ERC721Enumerable, Ownable, SimpleInitializable {
    using Strings for uint256;
    using Math for uint256;

    address public immutable collection;
    address private _vault;
    uint256 internal constant _decimals = 18;
    uint256 private _totalValue;
    uint256 private _nextId = 1;
    string private _baseTokenURI;

    mapping(uint256 => OptionPosition) internal _options;

    modifier onlyVault() {
        if (msg.sender != _vault) {
            revert OnlyVault(address(this), msg.sender, _vault);
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

    function openPosition(address to, uint256 strikeId, uint256 amount) public override onlyVault returns(uint256)
    {
        if(amount == 0) {
            revert ZeroAmount(address(this));
        }
        uint256 positionId = _nextId++;
        _options[positionId] = OptionPosition(strikeId, PositionState.PENDING, amount, 0);
        if(_optionType() == OptionType.LONG_CALL) {
            _totalValue += spotPrice(positionId);
        } else {
            _totalValue += strikePrice(positionId);
        }
        _safeMint(to, positionId);
        return positionId;
    }

    function activePosition(uint256 positionId, uint256 premium) public override onlyVault
    {
        OptionPosition storage po = _options[positionId];
        if(po.state != PositionState.PENDING) {
            revert IsNotPending(address(this), positionId, po.state);
        }
        po.state = PositionState.ACTIVE;
        po.premium = premium;
    }

    function closePosition(uint256 positionId) public override onlyVault
    {
        if(_options[positionId].state != PositionState.ACTIVE) {
            revert IsNotActive(address(this), positionId, _options[positionId].state);
        }
        _closePosition(positionId);
    }

    function forceClosePosition(uint256 positionId) public override onlyVault
    {
        if(_options[positionId].state != PositionState.PENDING) {
            revert IsNotPending(address(this), positionId, _options[positionId].state);
        }
        _closePosition(positionId);
    }

    function _closePosition(uint256 positionId) internal {
        if(_optionType() == OptionType.LONG_CALL) {
            _totalValue -= spotPrice(positionId);
        } else {
            _totalValue -= strikePrice(positionId);
        }
        delete _options[positionId];
        _burn(positionId);
    }

    function totalValue() public override view returns(uint256) 
    {
        return(_totalValue);
    }

    function strikePrice(uint256 positionId) public view override returns(uint256) {
        OptionPosition memory po = _options[positionId];
        return IVault(_vault).strike(po.strikeId).strikePrice.mulDiv(po.amount, 10 ** _decimals, Math.Rounding.Up);
    }

    function spotPrice(uint256 positionId) public view override returns(uint256) {
        OptionPosition memory po = _options[positionId];
        return IVault(_vault).strike(po.strikeId).spotPrice.mulDiv(po.amount, 10 ** _decimals, Math.Rounding.Up);
    }

    function optionPosition(uint256 positionId) public view override returns(OptionPosition memory) {
        return _options[positionId];
    }

    function optionPositionState(uint256 positionId) public view override returns(PositionState) {
        return _options[positionId].state;
    }

    function _optionType() internal pure virtual returns(OptionType);
}