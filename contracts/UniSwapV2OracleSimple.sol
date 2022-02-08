// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IPriceOracle.sol";

struct Pair {
    address addr;
    uint8 wbchIdx;
    uint8 usdDecimals;
    uint priceCumulativeOld;
    uint timestampOld;
    uint priceCumulativeNew;
    uint timestampNew;
}

contract UniSwapV2OracleSimple is Ownable, IPriceOracle {
    using SafeMath for uint;

    address public immutable WBCH;
    uint public constant CYCLE = 30 minutes;

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

        uint priceCumulative = currentCumulativePrice(pairAddr, wbchIdx);
        pairs.push(Pair(pairAddr, wbchIdx, usdDecimals, 
            priceCumulative, block.timestamp, 
            priceCumulative, block.timestamp));
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
        uint ts = block.timestamp;
        if (ts - timestampLast < CYCLE) {
            return;
        }

        timestampLast = ts;
        for (uint i = 0; i < pairs.length; i++) {
            Pair memory pair = pairs[i];
            pair.priceCumulativeOld = pair.priceCumulativeNew;
            pair.timestampOld = pair.timestampNew;
            pair.priceCumulativeNew = currentCumulativePrice(pair.addr, pair.wbchIdx);
            pair.timestampNew = ts;
            pairs[i] = pair;
        }
    }

    function getPrice() public override returns (uint) {
        update();
        return getPriceWithoutUpdate();
    }

    function getPriceWithoutUpdate() public view returns (uint) {        
        uint nPairs = pairs.length;
        uint priceSum;
        for (uint i = 0; i < nPairs; i++) {
            Pair memory pair = pairs[i];
            priceSum += getPairPrice(pair);
        }
        return (priceSum / nPairs) * (10**18) / (2**112);
    }

    function getPairPrice(Pair memory pair) private view returns (uint) {
        uint priceCumulative = currentCumulativePrice(pair.addr, pair.wbchIdx);
        uint price = (priceCumulative - pair.priceCumulativeOld) / (block.timestamp - pair.timestampOld);

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

}
