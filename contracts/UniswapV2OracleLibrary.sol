// https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2OracleLibrary.sol
pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV2OracleLibrary {
    using FixedPoint for *;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrice(
        address pair, uint8 tokenIdx
    ) internal view returns (uint priceCumulative, uint112 reserve) {
        uint32 blockTimestamp = currentBlockTimestamp();
        priceCumulative = tokenIdx == 0
            ? IUniswapV2Pair(pair).price0CumulativeLast()
            : IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        reserve = tokenIdx == 0 ? reserve0 : reserve1;
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            if (tokenIdx == 0) {
                priceCumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            } else {
                priceCumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
            }
        }
    }
}
