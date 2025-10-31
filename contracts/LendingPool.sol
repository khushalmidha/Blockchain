// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Simple Lending Pool (OpenZeppelin-based)
/// @notice Minimal educational example for lending & borrowing using OpenZeppelin utilities.
contract LendingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public asset; // token lent out (e.g., DAI)
    IERC20 public collateralToken; // token used as collateral (e.g., WETH mock)

    // price variables use 18 decimals (1e18 = 1)
    uint256 public assetPrice = 1e18; // default: asset = 1 USD
    uint256 public collateralPrice = 1e18; // default: collateral = 1 USD

    // loan-to-value expressed in 1e18 (e.g., 0.5 = 0.5e18)
    uint256 public ltv = 5e17; // 50%

    uint256 public totalLiquidity; // amount of asset available in pool

    uint256 public nextLoanId = 1;

    struct Loan {
        address borrower;
        uint256 collateralAmount;
        uint256 debt; // amount of asset borrowed outstanding
        bool open;
    }

    mapping(uint256 => Loan) public loans;

    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Borrow(address indexed borrower, uint256 loanId, uint256 collateralAmount, uint256 amount);
    event Repay(address indexed borrower, uint256 loanId, uint256 amount, bool closed);
    event Liquidate(address indexed liquidator, uint256 loanId, uint256 repaid, uint256 collateralSeized);

    constructor(IERC20 _asset, IERC20 _collateralToken) {
        asset = _asset;
        collateralToken = _collateralToken;
    }

    /* Admin setters */
    function setPrices(uint256 _assetPrice, uint256 _collateralPrice) external onlyOwner {
        require(_assetPrice > 0 && _collateralPrice > 0, "prices>0");
        assetPrice = _assetPrice;
        collateralPrice = _collateralPrice;
    }

    function setLTV(uint256 _ltv) external onlyOwner {
        require(_ltv <= 1e18, "ltv<=1");
        ltv = _ltv;
    }

    /* Lender functions */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount>0");
        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalLiquidity += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant onlyOwner {
        // For simplicity, only owner (instructor) can withdraw pool funds in this example.
        require(amount <= totalLiquidity, "insufficient liquidity");
        totalLiquidity -= amount;
        asset.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    /* Borrower functions */
    function borrow(uint256 collateralAmount, uint256 borrowAmount) external nonReentrant returns (uint256) {
        require(collateralAmount > 0 && borrowAmount > 0, "positive amounts");
        // Transfer collateral
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Compute maximum borrowable based on collateral value and LTV
        uint256 collateralValue = (collateralAmount * collateralPrice) / 1e18;
        uint256 maxBorrow = (collateralValue * ltv) / 1e18;
        require(borrowAmount <= maxBorrow, "exceeds max borrowable");
        require(borrowAmount <= totalLiquidity, "not enough liquidity");

        // Create loan
        uint256 loanId = nextLoanId++;
        loans[loanId] = Loan({borrower: msg.sender, collateralAmount: collateralAmount, debt: borrowAmount, open: true});

        // Transfer asset to borrower
        totalLiquidity -= borrowAmount;
        asset.safeTransfer(msg.sender, borrowAmount);

        emit Borrow(msg.sender, loanId, collateralAmount, borrowAmount);
        return loanId;
    }

    function repay(uint256 loanId, uint256 amount) external nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.open, "loan closed");
        require(amount > 0, "amount>0");
        require(msg.sender == loan.borrower, "only borrower");

        // Transfer asset from borrower
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (amount >= loan.debt) {
            // fully repaid
            uint256 repayAmount = loan.debt;
            loan.debt = 0;
            loan.open = false;
            totalLiquidity += repayAmount;
            // return collateral
            collateralToken.safeTransfer(loan.borrower, loan.collateralAmount);
            emit Repay(msg.sender, loanId, repayAmount, true);
        } else {
            loan.debt -= amount;
            totalLiquidity += amount;
            emit Repay(msg.sender, loanId, amount, false);
        }
    }

    /* Liquidation: anyone can liquidate under-collateralized loans by repaying the debt and seizing collateral */
    function liquidate(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.open, "loan closed");

        uint256 collateralValue = (loan.collateralAmount * collateralPrice) / 1e18;
        uint256 maxBorrow = (collateralValue * ltv) / 1e18;
        require(loan.debt > maxBorrow, "healthy loan");

        // Liquidator repays the debt
        uint256 repayAmount = loan.debt;
        asset.safeTransferFrom(msg.sender, address(this), repayAmount);
        totalLiquidity += repayAmount;

        // Transfer collateral to liquidator
        uint256 seized = loan.collateralAmount;
        loan.open = false;
        loan.debt = 0;
        collateralToken.safeTransfer(msg.sender, seized);

        emit Liquidate(msg.sender, loanId, repayAmount, seized);
    }
}
