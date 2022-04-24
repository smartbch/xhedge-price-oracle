// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.0;

import "./IPriceOracle.sol";

// Debug PriceOracle for smartbch mainnet
contract FixedOracle is IPriceOracle {

    function getPrice() public pure override returns (uint) {
        return 350 * (10 ** 18);
    }

}
