// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./MockPriceOracle.sol";

contract LendingPool {
    using SafeMath for uint256;

    address public owner;
    uint256 public totalDeposits;
    uint256 public totalBorrowed;
    uint256 public fixedInterestRate; // In percentage, e.g., 5% = 500
    IERC20 public collateralToken;
    MockPriceOracle public priceOracle;
    uint256 public collateralToEthRatio; // In percentage, e.g., 150% = 15000

    struct UserData {
        uint256 depositAmount;
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 borrowTimestamp;
    }

    mapping(address => UserData) public users;

    constructor(
        uint256 _fixedInterestRate,
        address _collateralTokenAddress,
        address _priceOracleAddress,
        uint256 _collateralToEthRatio
    ) {
        owner = msg.sender;
        fixedInterestRate = _fixedInterestRate;
        collateralToken = IERC20(_collateralTokenAddress);
        priceOracle = MockPriceOracle(_priceOracleAddress);
        collateralToEthRatio = _collateralToEthRatio;
    }

    function deposit() external payable {
        users[msg.sender].depositAmount = users[msg.sender].depositAmount.add(
            msg.value
        );
        totalDeposits = totalDeposits.add(msg.value);
    }

    function borrow(uint256 _amount) external {
        require(
            _amount <= totalDeposits.sub(totalBorrowed),
            "Not enough liquidity"
        );
        users[msg.sender].borrowedAmount = _amount;
        users[msg.sender].borrowTimestamp = block.timestamp;
        totalBorrowed = totalBorrowed.add(_amount);
        payable(msg.sender).transfer(_amount);
    }

    function repay() external payable {
        uint256 principal = users[msg.sender].borrowedAmount;
        uint256 interest = calculateInterest(
            principal,
            users[msg.sender].borrowTimestamp
        );
        uint256 totalRepayment = principal.add(interest);

        require(msg.value >= totalRepayment, "Insufficient repayment amount");

        users[msg.sender].borrowedAmount = 0;
        users[msg.sender].borrowTimestamp = 0;
        totalBorrowed = totalBorrowed.sub(principal);

        // Refund any excess payment
        if (msg.value > totalRepayment) {
            payable(msg.sender).transfer(msg.value.sub(totalRepayment));
        }
    }

    function withdraw(uint256 _amount) external {
        require(
            _amount <= users[msg.sender].depositAmount,
            "Insufficient deposit balance"
        );
        users[msg.sender].depositAmount = users[msg.sender].depositAmount.sub(
            _amount
        );
        totalDeposits = totalDeposits.sub(_amount);
        payable(msg.sender).transfer(_amount);
    }

    function calculateInterest(
        uint256 _principal,
        uint256 _borrowTimestamp
    ) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp.sub(_borrowTimestamp);
        uint256 interest = _principal
            .mul(fixedInterestRate)
            .mul(timeElapsed)
            .div(10000)
            .div(365 days);
        return interest;
    }

    function m(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        collateralToken.transferFrom(msg.sender, address(this), _amount);
        users[msg.sender].collateralAmount = users[msg.sender]
            .collateralAmount
            .add(_amount);
    }

    function withdrawCollateral(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            users[msg.sender].collateralAmount >= _amount,
            "Insufficient collateral balance"
        );
        require(
            isBorrowSafeAfterWithdraw(msg.sender, _amount),
            "Withdraw would result in unsafe borrow"
        );

        users[msg.sender].collateralAmount = users[msg.sender]
            .collateralAmount
            .sub(_amount);
        collateralToken.transfer(msg.sender, _amount);
    }

    function getMaxBorrowableAmount(
        address _user
    ) public view returns (uint256) {
        uint256 collateralValueInEth = getCollateralValueInEth(_user);
        uint256 maxBorrowable = collateralValueInEth
            .mul(collateralToEthRatio)
            .div(10000); // Based on collateralToEthRatio
        return maxBorrowable;
    }

    function getCollateralValueInEth(
        address _user
    ) public view returns (uint256) {
        uint256 collateralAmount = users[_user].collateralAmount;
        uint256 collateralPrice = priceOracle.getLatestPrice();
        uint256 decimals = priceOracle.getDecimals();
        uint256 collateralValue = uint256(collateralPrice)
            .mul(collateralAmount)
            .div(10 ** decimals);
        return collateralValue;
    }

    function isBorrowSafeAfterWithdraw(
        address _user,
        uint256 _withdrawAmount
    ) public view returns (bool) {
        uint256 collateralAmountAfterWithdraw = users[_user]
            .collateralAmount
            .sub(_withdrawAmount);
        uint256 collateralValueInEthAfterWithdraw = uint256(
            priceOracle.getLatestPrice()
        ).mul(collateralAmountAfterWithdraw).div(
                10 ** priceOracle.getDecimals()
            );
        uint256 maxBorrowableAfterWithdraw = collateralValueInEthAfterWithdraw
            .mul(collateralToEthRatio)
            .div(10000);
        return users[_user].borrowedAmount <= maxBorrowableAfterWithdraw;
    }
}
