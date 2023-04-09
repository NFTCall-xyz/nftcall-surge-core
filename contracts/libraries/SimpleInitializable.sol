//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

abstract contract SimpleInitializable {
  bool internal _initialized = false;

  modifier initializer() {
    if (_initialized) {
      revert AlreadyInitialised(address(this));
    }
    _initialized = true;
    _;
  }

  error AlreadyInitialised(address target);
}
