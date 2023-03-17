// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC721Metadata, ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IOptionBase} from "../interfaces/IOptionBase.sol";

abstract contract OptionBase is IOptionBase, ERC721Enumerable, Ownable {
    using Strings for uint256;

    address public immutable collection;
    uint256 private _totalValue;
    string private _namePrefix;
    string private _namePostfix;
    string private _symbolPrefix;
    string private _symbolPostfix;
    string private _baseTokenURI;

    struct OptionData {
        uint8 strikePriceIndex;
        uint8 durationIndex;
        uint40 endTime;
        uint256 strikePrice;
        uint256 amount;
    }

    mapping(uint256 => OptionData) internal _options;

    constructor(address collectionAddress, string memory namePrefix, string memory namePostfix, string memory symbolPrefix, string memory symbolPostfix, string memory baseURI)
        ERC721("", "") Ownable()
    {
        collection = collectionAddress;
        _namePrefix = namePrefix;
        _namePostfix = namePostfix;
        _symbolPrefix = symbolPrefix;
        _symbolPostfix = symbolPostfix;
        _baseTokenURI = baseURI;
    }

    function name() public view override returns(string memory) 
    {
        return string(abi.encodePacked(_namePrefix, IERC721Metadata(collection).name(), _namePostfix));
    }

    function symbol() public view override returns(string memory) 
    {
        return string(abi.encodePacked(_symbolPrefix, IERC721Metadata(collection).symbol(), _symbolPostfix));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) 
    {
        string memory baseURI = _baseTokenURI;
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function mint(address to, uint8 strikePriceIndex, uint8 durationIndex, uint40 endTime, uint256 strikePrice, uint256 tokenId, uint256 amount) public override onlyOwner
    {
        _options[tokenId] = OptionData(strikePriceIndex, durationIndex, endTime, strikePrice, amount);
        // TODO: the locked value of a call option should be the openPrice
        _totalValue += strikePrice;
        emit OptionPositionOpened(to, tokenId, strikePriceIndex, durationIndex, endTime, strikePrice, amount);
        emit Mint(to, tokenId);
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) public override onlyOwner
    {
        address owner = ERC721.ownerOf(tokenId);
        // TODO: the locked value of a call option should be the openPrice
        _totalValue -= _options[tokenId].strikePrice;
        emit Burn(owner, tokenId);
        delete _options[tokenId];
        _burn(tokenId);
    }

    function totalValue() public override view returns(uint256) 
    {
        return(_totalValue);
    }
}