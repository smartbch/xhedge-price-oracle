// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.0;

import "./UniSwapV2Oracle.sol";

contract TestUpdater {

    address public immutable oracle;

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function update() public {
        UniSwapV2Oracle(oracle).update();
    }
    function updateReserveOfPair(uint idx) public {
        UniSwapV2Oracle(oracle).updateReserveOfPair(idx);
    }

}
