// SPDX-License-Identifier: Apache
pragma solidity >=0.6.6;

interface IPriceOracle {
    function getPrice() external returns (uint);
}
