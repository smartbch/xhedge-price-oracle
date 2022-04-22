// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IPriceOracle.sol";


// References:
// https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol
// https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleOracleSimple.sol


struct Observation {
    uint timestamp;
    uint priceCumulative;
    uint wbchReserve;
}

struct Pair {
    address addr;
    uint8 wbchIdx;
    uint8 usdDecimals;
    Observation[] observations;
}

contract UniSwapV2Oracle is IPriceOracle {
    using SafeMath for uint;

    // params of moving averages
    uint public constant WINDOW_SIZE = 12 hours;
    uint8 public constant GRANULARITY = 24;
    uint public constant PERIOD_SIZE = WINDOW_SIZE / GRANULARITY; // 30 minutes

    Pair[] private pairs;
    uint private avgPrice; // updated after sampling pairs
    uint public lastUpdatedTime;

    constructor(address wbchAddr, address[] memory pairAddrs) {
        for (uint i = 0; i < pairAddrs.length; i++) {
            addPair(wbchAddr, pairAddrs[i]);
        }
        update();
    }

    function addPair(address wbchAddr, address pairAddr) private {
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

        for (uint i = 0; i < GRANULARITY; i++) {
            newPair.observations.push(Observation(0, 0, 0));
        }
    }

    function getPairs() public view returns(Pair[] memory) {
        return pairs;
    }

    // debug
    function viewPrice() public view returns (uint) {
        return avgPrice;
    }
    function viewPriceOfPair(uint i) public view returns (uint price, uint weight) {
        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        uint8 firstObservationIndex = (currObservationIndex + 1) % GRANULARITY;
        price = getPairPriceUQ112x112(pairs[i], firstObservationIndex, currObservationIndex) * (10**18) / (2**112);
        weight = getMinWbchReserve(pairs[i].observations);
    }
 
    // return avg price, update it first if needed
    function getPrice() public override returns (uint) {
        update(); // do sampling & price calc if needed
        require(avgPrice > 0, 'Oracle: NOT_READY');
        return avgPrice;
    }

    // update the cumulative price and WBCH reserve for observations at the current timestamp. 
    // these observations are updated at most once per epoch period.
    function update() public {
        uint timeElapsed = block.timestamp - lastUpdatedTime;
        if (timeElapsed < PERIOD_SIZE) {
            return;
        }

        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        uint8 firstObservationIndex = (currObservationIndex + 1) % GRANULARITY;

        // update observations
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            updatePairObservation(pair, currObservationIndex);
        }

        // calc reserve-weighted avg price
        avgPrice = calcWeightedAvgPrice(firstObservationIndex, currObservationIndex);
        lastUpdatedTime = block.timestamp;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint timestamp) private pure returns (uint8 index) {
        uint epochPeriod = timestamp / PERIOD_SIZE;
        return uint8(epochPeriod % GRANULARITY);
    }

    // update the cumulative price and WBCH reserve for the specific observation
    function updatePairObservation(Pair storage pair, uint8 observationIndex) private {
        (address pairAddr, uint8 wbchIdx) = (pair.addr, pair.wbchIdx);

        Observation storage observation = pair.observations[observationIndex];
        observation.timestamp = block.timestamp;

        // price0CumulativeLast = token1/token0
        // price1CumulativeLast = token0/token1
        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pairAddr);
        observation.priceCumulative = wbchIdx == 0 ? price0Cumulative : price1Cumulative;

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pairAddr).getReserves();
        observation.wbchReserve = wbchIdx == 0 ? reserve0 : reserve1;
    }

    function calcWeightedAvgPrice(uint8 firstObservationIndex, 
                                  uint8 currObservationIndex) private view returns (uint) {
        uint priceSum;
        uint rSum;
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            uint r = getMinWbchReserve(pair.observations);
            priceSum += getPairPriceUQ112x112(pair, firstObservationIndex, currObservationIndex) * r;
            rSum += r;
        }
        if (rSum == 0) {
            return 0; // oracle is not ready
        } else {
            return (priceSum / rSum) * (10**18) / (2**112);
        }
    }

    function getMinWbchReserve(Observation[] storage observations) private view returns (uint) {
        uint minR = type(uint).max;
        for (uint i = 0; i < observations.length; i++) {
            uint r = observations[i].wbchReserve;
            if (r < minR) {
                minR = r;
            }
        }
        return minR;
    }

    function getPairPriceUQ112x112(Pair storage pair, 
                                   uint8 firstObservationIndex, 
                                   uint8 currObservationIndex) private view returns (uint) {
        Observation storage firstObservation = pair.observations[firstObservationIndex];
        Observation storage currObservation = pair.observations[currObservationIndex];

        uint priceDiff = currObservation.priceCumulative - firstObservation.priceCumulative;
        uint timeDiff = currObservation.timestamp - firstObservation.timestamp;
        uint price = (priceDiff / timeDiff);

        // align decimals
        uint8 usdDec = pair.usdDecimals;
        if (usdDec > 18) {
            price /= (10 ** (usdDec - 18));
        } else if (usdDec < 18) {
            price *= (10 ** (18 - usdDec));
        }
        return price;
    }

    // fix mising observations of given epoch
    function fixObservations(uint8 idx) public {
        require(idx != observationIndexOf(block.timestamp), 'Oracle: SHOULD_CALL_UPDATE');
        require(block.timestamp - pairs[0].observations[idx].timestamp > WINDOW_SIZE, 'Oracle: NO_NEED_TO_FIX');
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            updatePairObservation(pair, idx);
        }
    }

}
