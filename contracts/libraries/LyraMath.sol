//SPDX-License-Identifier: ISC
pragma solidity ^0.8.17;
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @title LyraMath
 * @author Lyra
 * @dev Library to unify logic for common shared functions
 */
library LyraMath {
  /// @dev Return the minimum value between the two inputs
  function min(uint x, uint y) internal pure returns (uint) {
    return (x < y) ? x : y;
  }

  /// @dev Return the maximum value between the two inputs
  function max(uint x, uint y) internal pure returns (uint) {
    return (x > y) ? x : y;
  }

  /// @dev Compute the absolute value of `val`.
  function abs(int val) internal pure returns (uint) {
    return uint(val < 0 ? -val : val);
  }

  /// @dev Takes ceiling of a to m precision
  /// @param m represents 1eX where X is the number of trailing 0's
  function ceil(uint a, uint m) internal pure returns (uint) {
    return ((a + m - 1) / m) * m;
  }

  function flag(int val) internal pure returns (int) {
    if(val < 0) {
      return -1;
    } else if(val > 0) {
      return 1;
    } else {
      return 0;
    }
  }

  function flagAbs(int val) internal pure returns (int, uint) {
    if(val < 0) {
      return (-1, uint(-val));
    } else if(val > 0) {
      return (1, uint(val));
    } else {
      return (0, 0);
    }
  }

  function iMulDiv(int a, int b, uint denominator, Math.Rounding rounding) internal pure returns(int) {
    (int flagA, uint absA) = flagAbs(a);
    (int flagB, uint absB) = flagAbs(b);
    return flagA * flagB * int(Math.mulDiv(absA, absB, denominator, rounding));
  }
}
