// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./UniswapV2OracleLibrary.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";
// import "hardhat/console.sol";
import "./IPriceOracle.sol";

// References:
// https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol
// https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleOracleSimple.sol


contract UniSwapV2Oracle is IPriceOracle {
    // using SafeMath for uint;

    event UpdateObservations(address indexed caller, uint newAvgPrice, uint updatedTime);
    event UpdateWbchReserve(address indexed caller, uint pairIdx, uint wbchReserve, uint updatedTime);

    uint private constant EOACODEHASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    // params of moving averages
    uint private constant WINDOW_SIZE = 12 hours;
    uint8 private constant GRANULARITY = 24;
    uint private constant PERIOD_SIZE = WINDOW_SIZE / GRANULARITY; // 30 minutes

    struct Observation {
        uint64 timestamp;
        uint112 wbchReserve; // 21M * 10**18 needs only 85 bits
        uint priceCumulative;
    }
    
    struct Pair {
        address addr;
        uint8 wbchIdx;
        uint8 usdDecimals;
        Observation[GRANULARITY] observations;
    }

    Pair[] private pairs;
    uint192 public avgPrice; // updated after sampling pairs
    uint64 public priceWinodwSize;

    constructor(address wbchAddr, address[] memory pairAddrs) {
        for (uint i = 0; i < pairAddrs.length; i++) {
            addPair(wbchAddr, pairAddrs[i]);
        }
        update();
    }

    modifier onlyEOA() {
        uint codeHash;
        address sender = msg.sender;
        assembly { codeHash := extcodehash(sender) }
        require(codeHash == EOACODEHASH, "Oracle: NOT_EOA");
        _;
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
    }

    function getPairs() public view returns(Pair[] memory) {
        return pairs;
    }

    // debug
    function getLastUpdatedTime() public view returns (uint64) {
        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        return pairs[0].observations[currObservationIndex].timestamp;
    }
    function getPriceOfPair(uint idx) public view returns (uint price, uint weight) {
        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        uint8 firstObservationIndex = (currObservationIndex + 1) % GRANULARITY;
        price = getPairPriceUQ112x112(pairs[idx], firstObservationIndex, currObservationIndex) * (10**18) / (2**112);
        weight = getMinWbchReserve(pairs[idx].observations);
    }
 
    // return avg price, update it first if needed
    function getPrice() public override view returns (uint) {
        // update(); // do sampling & price calc if needed
        require(avgPrice > 0, 'Oracle: NOT_READY');
        require(priceWinodwSize < WINDOW_SIZE + PERIOD_SIZE, 'Oracle: MISSING_HISTORICAL_OBSERVATION');
        return avgPrice;
    }

    // update the cumulative price and WBCH reserve for observations at the current timestamp. 
    // these observations are updated at most once per epoch period.
    function update() public onlyEOA {
        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        // console.log('currObservationIndex: %d', currObservationIndex);
        uint timeElapsed = block.timestamp - pairs[0].observations[currObservationIndex].timestamp;
        if (timeElapsed < PERIOD_SIZE) {
            return;
        }

        // update observations
        for (uint i = 0; i < pairs.length; i++) {
            Pair storage pair = pairs[i];
            updatePairObservation(pair, currObservationIndex);
        }

        // calc reserve-weighted avg price
        uint8 firstObservationIndex = (currObservationIndex + 1) % GRANULARITY;
        avgPrice = uint192(calcWeightedAvgPrice(firstObservationIndex, currObservationIndex));
        priceWinodwSize = uint64(block.timestamp) - pairs[0].observations[firstObservationIndex].timestamp;
        emit UpdateObservations(msg.sender, avgPrice, block.timestamp);
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
        observation.timestamp = uint64(block.timestamp);

        // price0CumulativeLast = token1/token0
        // price1CumulativeLast = token0/token1
        observation.priceCumulative = UniswapV2OracleLibrary.currentCumulativePrice(pairAddr, wbchIdx);

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
            priceSum += getPairPriceUQ112x112(pair, firstObservationIndex, currObservationIndex) * r; // never overflow
            rSum += r;
        }
        if (rSum == 0) {
            return 0; // oracle is not ready
        } else {
            return ((priceSum / rSum) * (10**18))>>112;
        }
    }

    function getMinWbchReserve(Observation[GRANULARITY] storage observations) private view returns (uint) {
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

        assert(currObservation.timestamp > firstObservation.timestamp);
        uint priceDiff = currObservation.priceCumulative - firstObservation.priceCumulative;
        uint timeDiff = currObservation.timestamp - firstObservation.timestamp;
        uint price = priceDiff / timeDiff;

        // align decimals
        uint8 usdDec = pair.usdDecimals;
        if (usdDec > 18) {
            price /= (10 ** (usdDec - 18));
        } else if (usdDec < 18) {
            price *= (10 ** (18 - usdDec));
        }
        // suppose BCH's price is forever under 16.78M (2**24) USD, it takes at most 24+112=136 bits.
        return price;
    }

    // update WBCH reserve for observation of the given pair at the current time period. 
    function updateReserveOfPair(uint idx) public onlyEOA {
        require(idx < pairs.length, 'Oracle: INVALID_PAIR_IDX');
        Pair storage pair = pairs[idx];
        (address pairAddr, uint8 wbchIdx) = (pair.addr, pair.wbchIdx);
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pairAddr).getReserves();
        uint112 wbchReserve = wbchIdx == 0 ? reserve0 : reserve1;

        uint8 currObservationIndex = observationIndexOf(block.timestamp);
        Observation storage observation = pair.observations[currObservationIndex];
        if (wbchReserve < observation.wbchReserve) {
            observation.wbchReserve = wbchReserve;
            emit UpdateWbchReserve(msg.sender, idx, wbchReserve, block.timestamp);
        }
    }

}
