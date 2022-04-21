// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./IPriceOracle.sol";

// Debug PriceOracle for smartbch mainnet
contract FixedOracle is IPriceOracle {

    function getPrice() public view override returns (uint) {
        return 350 * (10 ** 18);
    }

}
