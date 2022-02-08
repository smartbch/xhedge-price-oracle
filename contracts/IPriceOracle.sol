// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IPriceOracle {
    function getPrice() external returns (uint);
}
