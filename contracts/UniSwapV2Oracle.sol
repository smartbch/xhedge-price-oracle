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
    uint64 effectiveTime;
    Observation[] observations;
}

contract UniSwapV2Oracle is Ownable, IPriceOracle {
    using SafeMath for uint;

    address public immutable WBCH_ADDR; // 0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04;
    uint public constant WINDOW_SIZE = 12 hours;
    uint8 public constant GRANULARITY = 24;
    uint public constant PERIOD_SIZE = WINDOW_SIZE / GRANULARITY; // 30 minutes
    uint public constant NEW_PAIR_DELAY_TIME = 3 days;

    Pair[] public pairs;
    uint lastSamplingTime;
    uint avgPrice;

    constructor(address wbchAddr, address[] memory pairAddrs) {
        WBCH_ADDR = wbchAddr;
        for (uint i = 0; i < pairAddrs.length; i++) {
            _addPair(wbchAddr, pairAddrs[i]);
        }
    }

    function addPair(address pairAddr) public onlyOwner {
        _addPair(WBCH_ADDR, pairAddr);
    }

    function _addPair(address wbchAddr, address pairAddr) private {
        address token0 = IUniswapV2Pair(pairAddr).token0();
        address token1 = IUniswapV2Pair(pairAddr).token1();

        uint8 wbchIdx;
        uint8 usdDecimals;
        if (token0 == wbchAddr) {
            wbchIdx = 0;
            usdDecimals = IERC20(token1).decimals();
        } else {
            require(token1 == wbchAddr, "Oracle: WBCH_NOT_IN_PAIR");
            wbchIdx = 1;
            usdDecimals = IERC20(token0).decimals();
        }

        pairs.push();
        Pair storage newPair = pairs[pairs.length - 1];
        newPair.addr = pairAddr;
        newPair.wbchIdx = wbchIdx;
        newPair.usdDecimals = usdDecimals;
        newPair.effectiveTime = uint64(block.timestamp + NEW_PAIR_DELAY_TIME);

        // uint priceCumulative = currentCumulativePrice(pairAddr, wbchIdx);
        for (uint i = 0; i < GRANULARITY; i++) {
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

    function getPrice() public override returns (uint) {
        update(); // do sampling & price calc if needed
        return avgPrice;
    }

    function update() public {
        uint timeElapsed = block.timestamp - lastSamplingTime;
        if (timeElapsed < PERIOD_SIZE) {
            return;
        }

        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        uint8 firstObservationIndex = (currObservationIndex + 1) % GRANULARITY;

        // update observations
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            Observation storage observation = pair.observations[currObservationIndex];
            observation.timestamp = block.timestamp;
            observation.k = IUniswapV2Pair(pair.addr).kLast();
            observation.priceCumulative = currentCumulativePrice(pair.addr, pair.wbchIdx);
        }

        // update k-weighted avg price
        avgPrice = calcKWeightedAvgPrice(firstObservationIndex, currObservationIndex);
        lastSamplingTime = block.timestamp;
    }

    function calcKWeightedAvgPrice(uint8 firstObservationIndex, 
                                   uint8 currObservationIndex) private view returns (uint) {
        uint priceSum;
        uint kSum;
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            if (pair.effectiveTime > block.timestamp) {
                uint k = getMinK(pair.observations);
                priceSum += getPairPrice(pair, firstObservationIndex, currObservationIndex) * k;
                kSum += k;
            }
        }
        require(kSum > 0, 'Oracle: NO_EFFECTIVE_PAIRS');
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

    function getPairPrice(Pair storage pair, 
                          uint8 firstObservationIndex, 
                          uint8 currObservationIndex) private view returns (uint) {
        Observation storage firstObservation = pair.observations[firstObservationIndex];
        Observation storage currObservation = pair.observations[currObservationIndex];

        uint priceDiff = currObservation.priceCumulative - firstObservation.priceCumulative;
        uint timeDiff = currObservation.timestamp - firstObservation.timestamp;
        uint price = priceDiff / timeDiff;

        // align decimals
        uint8 usdDec = pair.usdDecimals;
        if (usdDec > 18) {
            price /= (10 ** (18 - usdDec));
        } else if (usdDec < 18) {
            price *= (10 ** (usdDec - 18));
        }
        return price;
    }

    // price0CumulativeLast = token1/token0
    // price1CumulativeLast = token0/token1
    function currentCumulativePrice(address pair, uint8 wbchIdx) private view returns (uint) {
        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        return wbchIdx == 0 ? price0Cumulative : price1Cumulative;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint timestamp) public pure returns (uint8 index) {
        uint epochPeriod = timestamp / PERIOD_SIZE;
        return uint8(epochPeriod % GRANULARITY);
    }

}
