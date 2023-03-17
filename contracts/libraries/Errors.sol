// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

library Errors {
    string public constant V_INVALID_AMOUNT = '1';
    string public constant V_NOT_ENOUGH_USER_BALANCE = '2';
    string public constant MATH_MULTIPLICATION_OVERFLOW = '3';
    string public constant MATH_DIVISION_BY_ZERO = '4';
    string public constant MATH_ADDITION_OVERFLOW = '5';

}

library ErrorCodes {
    uint256 public constant V_INVALID_AMOUNT = 1;
    uint256 public constant V_NOT_ENOUGH_USER_BALANCE = 2;
    uint256 public constant MATH_MULTIPLICATION_OVERFLOW = 3;
    uint256 public constant MATH_DIVISION_BY_ZERO = 4;
    uint256 public constant MATH_ADDITION_OVERFLOW = 5;
}