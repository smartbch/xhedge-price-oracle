// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {

    uint8 private dec;

    constructor(string memory symbol, uint256 initialSupply, uint8 _dec) ERC20(symbol, symbol) {
        dec = _dec;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return dec;
    }

}
