// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockPriceOracle {
    uint256 private price;
    uint8 private constant decimals = 8;

    constructor(uint256 _initialPrice) {
        price = _initialPrice;
    }

    function setPrice(uint256 _newPrice) external {
        price = _newPrice;
    }

    function getLatestPrice() external view returns (uint256) {
        return price;
    }

    function getDecimals() external pure returns (uint8) {
        return decimals;
    }
}
