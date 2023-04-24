// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MintableERC721 is ERC721Enumerable {
    uint256 public constant MAX_SUPPLY = 10000;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
    }

    function mint() public {
        uint256 ts = totalSupply();
        _safeMint(_msgSender(), ts + 1);
    }
}