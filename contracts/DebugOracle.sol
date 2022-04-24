// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./IPriceOracle.sol";

// Debug PriceOracle for smartbch mainnet
contract DebugOracle is IPriceOracle {

	// BenSwap, WBCH/flexUSD
    address constant PAIR_ADDR = address(0x65C042E455a6B84132c78E8FDaE058188e17c75A);
 // address constant WBCH_ADDR = address(0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04);
 // address constant FUSD_ADDR = address(0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72);

    function getPrice() public view override returns (uint) {
    	(uint rWBCH, uint rFUSD, ) = IUniswapV2Pair(PAIR_ADDR).getReserves();
    	return rFUSD * (10 ** 18) / rWBCH;
    }

}
