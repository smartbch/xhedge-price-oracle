// SPDX-License-Identifier: Apache
pragma solidity >=0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IPriceOracle.sol";

struct Pair {
    address addr;
    uint8 wbchIdx;
    uint priceAverage;
    uint priceCumulativeLast;
    uint timestampLast;
}

contract UniSwapV2OracleSimple is Ownable, IPriceOracle {
    using SafeMath for uint;

    address public constant WBCH = 0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04;
    uint public constant CYCLE = 30 minutes;

    Pair[] public pairs;
    uint timestampLast;

    constructor(address[] memory pairs) {
        for (uint i = 0; i < pairs.length; i++) {
            addPair(pairs[i]);
        }
    }

    function addPair(address pairAddr) public onlyOwner {
        uint8 wbchIdx;
        if (IUniswapV2Pair(pairAddr).token0() == WBCH) {
            wbchIdx = 0;
        } else {
            require(IUniswapV2Pair(pairAddr).token1() == WBCH, "Oracle: WBCH_NOT_IN_PAIR");
            wbchIdx = 1;
        }

        uint priceCumulative = currentCumulativePrice(pairAddr, wbchIdx);
        uint priceAverage = (priceCumulative / block.timestamp);
        pairs.push(Pair(pairAddr, wbchIdx, priceAverage, priceCumulative, block.timestamp));
    }

    function removePair(address pairAddr) public onlyOwner {
        uint nPairs = pairs.length;
        uint i;
        for (i = 0; i < nPairs; i++) {
            if (pairs[i].addr == pairAddr) {
                break;
            }
        }
        require(i < nPairs, "Oracle: PAIR_NOT_TRACKED");
        if (i < nPairs - 1) {
            pairs[i] = pairs[nPairs - 1];
        }
        pairs.pop();
    }

    function getPrice() external override returns (uint) {
        update();

        uint nPairs = pairs.length;
        uint priceSum;
        for (uint i = 0; i < nPairs; i++) {
            priceSum += pairs[i].priceAverage;
        }
        return (priceSum / nPairs) * (10**18) / (2**112);
    }

    function update() private {
        uint ts = block.timestamp;
        if (ts - timestampLast < CYCLE) {
            return;
        }

        timestampLast = ts;
        for (uint i = 0; i < pairs.length; i++) {
            Pair memory pair = pairs[i];
            uint timeElapsed = ts - pair.timestampLast;
            if (timeElapsed >= CYCLE) {
                uint priceCumulative = currentCumulativePrice(pair.addr, pair.wbchIdx);
                pair.priceAverage = ((priceCumulative - pair.priceCumulativeLast) / timeElapsed);
                pair.priceCumulativeLast = priceCumulative;
                pair.timestampLast = ts;
                pairs[i] = pair;
            }
        }
    }

    // price0CumulativeLast = token1/token0
    // price1CumulativeLast = token0/token1
    function currentCumulativePrice(address pair, uint8 wbchIdx) private view returns (uint) {
        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        return wbchIdx == 0 ? price0Cumulative : price1Cumulative;
    }

}
