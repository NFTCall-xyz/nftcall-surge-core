// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BackStopPool is Ownable {
    using SafeERC20 for IERC20;

    constructor()
        Ownable()
    {}

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(0), "BackStopPool: token is zero address");
        require(to != address(0), "BackStopPool: to is zero address");
        require(amount > 0, "BackStopPool: amount is zero");
        require(amount <= IERC20(token).balanceOf(address(this)), "BackStopPool: amount exceeds balance");
        IERC20(token).safeTransfer(to, amount);
    }
}