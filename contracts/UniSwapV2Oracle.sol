// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IPriceOracle.sol";


// References:
// https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol
// https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleOracleSimple.sol


struct Observation {
    uint timestamp;
    uint priceCumulative;
    uint k;
}

struct Pair {
    address addr;
    uint8 wbchIdx;
    uint8 usdDecimals;
    Observation[] observations;
}

contract UniSwapV2Oracle is Ownable, IPriceOracle {
    using SafeMath for uint;

    address public immutable WBCH;
    uint public constant CYCLE = 30 minutes;
    uint public constant windowSize = 12 hours;
    uint8 public constant granularity = 24;
    uint public constant periodSize = windowSize / granularity; // 30 minutes

    Pair[] public pairs;
    uint timestampLast;

    constructor(address _WBCH, address[] memory pairAddrs) {
        require(IERC20(_WBCH).decimals() == 18, "Oracle: BAD_WBCH_DECIMALS");
        WBCH = _WBCH;
        for (uint i = 0; i < pairAddrs.length; i++) {
            _addPair(pairAddrs[i], _WBCH);
        }
    }

    function addPair(address pairAddr) public onlyOwner {
        _addPair(pairAddr, WBCH);
    }

    function _addPair(address pairAddr, address _WBCH) private {
        address token0 = IUniswapV2Pair(pairAddr).token0();
        address token1 = IUniswapV2Pair(pairAddr).token1();

        uint8 wbchIdx;
        uint8 usdDecimals;
        if (token0 == _WBCH) {
            wbchIdx = 0;
            usdDecimals = IERC20(token1).decimals();
        } else {
            require(token1 == _WBCH, "Oracle: WBCH_NOT_IN_PAIR");
            wbchIdx = 1;
            usdDecimals = IERC20(token0).decimals();
        }

        pairs.push();
        Pair storage newPair = pairs[pairs.length - 1];
        newPair.addr = pairAddr;
        newPair.wbchIdx = wbchIdx;
        newPair.usdDecimals = usdDecimals;
        
        // uint priceCumulative = currentCumulativePrice(pairAddr, wbchIdx);
        for (uint i = 0; i < granularity; i++) {
            newPair.observations.push(Observation(0, 0, 0));
        }
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

    function update() public {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            Observation storage observation = pair.observations[observationIndex];

            // update priceCumulative
            uint timeElapsed = block.timestamp - observation.timestamp;
            if (timeElapsed > periodSize) {
                uint priceCumulative = currentCumulativePrice(pair.addr, pair.wbchIdx);
                observation.timestamp = block.timestamp;
                observation.priceCumulative = priceCumulative;
            }

            // update k
            uint k = IUniswapV2Pair(pair.addr).kLast();
            if (k < observation.k) {
                observation.k = k;
            }
        }
    }

    function getPrice() public override returns (uint) {
        // update();
        return getPriceWithoutUpdate();
    }

    function getPriceWithoutUpdate() public view returns (uint) {
        uint priceSum;
        uint kSum;
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            uint k = getMinK(pair.observations);
            if (k > 0) {
                priceSum += getPairPrice(pair) * k;
                kSum += k;
            }
        }
        return (priceSum / kSum) * (10**18) / (2**112);
    }

    function getMinK(Observation[] storage observations) private view returns (uint) {
        uint minK = 0;
        for (uint i = 0; i < observations.length; i++) {
            uint k = observations[i].k;
            if (k > 0) {
                if (minK == 0 || k < minK) {
                    minK = k;
                }
            }
        }
        return minK;
    }

    function getPairPrice(Pair storage pair) private view returns (uint) {
        Observation storage firstObservation = getFirstObservationInWindow(pair);
        uint priceCumulativeOld = firstObservation.priceCumulative;
        uint priceCumulativeNow = currentCumulativePrice(pair.addr, pair.wbchIdx);
        uint price = (priceCumulativeNow - priceCumulativeOld) / (block.timestamp - firstObservation.timestamp);

        // align decimals
        uint8 usdDec = pair.usdDecimals;
        if (usdDec > 18) {
            price *= (10 ** (usdDec - 18));
        } else if (usdDec < 18) {
            price /= (10 ** (18 - usdDec));
        }
        return price;
    }

    // price0CumulativeLast = token1/token0
    // price1CumulativeLast = token0/token1
    function currentCumulativePrice(address pair, uint8 wbchIdx) private view returns (uint) {
        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        return wbchIdx == 0 ? price0Cumulative : price1Cumulative;
    }


    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow(Pair storage pair) private view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        // no overflow issue. if observationIndex + 1 overflows, result is still zero.
        uint8 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = pair.observations[firstObservationIndex];
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint timestamp) public pure returns (uint8 index) {
        uint epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

}
