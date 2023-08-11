// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MintableERC20 is ERC20, Ownable {
    mapping(address => bool) private _whitelistedAddresses;
    mapping(address => uint256) private _mintedAmounts;
    uint256 private _maxMintAmountPerUser;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialMaxMintAmountPerUser
    ) ERC20(name, symbol) {
        _maxMintAmountPerUser = initialMaxMintAmountPerUser;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);
        if (from == address(0) || to == address(0)) {
            return;
        }
        else {
            require(
                _whitelistedAddresses[to] || _whitelistedAddresses[from],
                "Recipient is not whitelisted"
            );
        }
    }

    function setWhitelistAddress(
        address account,
        bool whitelisted
    ) external onlyOwner {
        _whitelistedAddresses[account] = whitelisted;
    }

    function setMaxMintAmountPerUser(uint256 maxMintAmount) external onlyOwner {
        _maxMintAmountPerUser = maxMintAmount;
    }

    function mint() public {
        address to = _msgSender();
        require(
            _mintedAmounts[to] < _maxMintAmountPerUser,
            "You have already minted the maximum amount allowed."
        );

        uint256 mintAmount = _maxMintAmountPerUser -
        _mintedAmounts[to];

        _mintedAmounts[to] = _maxMintAmountPerUser;
        _mint(to, mintAmount);
    }

    function ownerMint(
        address to,
        uint256 mintAmount
    ) public onlyOwner {
        _mintedAmounts[to] += mintAmount;
        _mint(to, mintAmount);
    }
}
