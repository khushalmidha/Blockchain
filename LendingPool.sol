// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title LendingPool
 * @notice Simple lending and borrowing contract using OpenZeppelin libraries
 * @dev Supports deposit, borrow with collateral, repay, and liquidation
 */
contract LendingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Token used for lending (e.g., USDC, DAI)
    IERC20 public lendingToken;
    
    // Token used as collateral (e.g., WETH)
    IERC20 public collateralToken;

    // Price feed values (scaled by 1e18)
    uint256 public lendingTokenPrice = 1e18;  // Default: 1 USD
    uint256 public collateralTokenPrice = 1e18;  // Default: 1 USD
    
    // Loan-to-Value ratio (50% = 0.5e18)
    uint256 public loanToValueRatio = 5e17;
    
    // Total liquidity available in the pool
    uint256 public totalLiquidity;
    
    // Loan counter
    uint256 private nextLoanId = 1;

    struct Loan {
        address borrower;
        uint256 collateralAmount;
        uint256 borrowedAmount;
        bool isActive;
    }

    // Mapping from loan ID to Loan details
    mapping(uint256 => Loan) public loans;
    
    // Mapping from user to their deposited amount
    mapping(address => uint256) public deposits;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed borrower, uint256 loanId, uint256 collateralAmount, uint256 borrowedAmount);
    event Repaid(address indexed borrower, uint256 loanId, uint256 amount);
    event Liquidated(address indexed liquidator, uint256 loanId, uint256 collateralSeized);

    constructor(address _lendingToken, address _collateralToken) {
        require(_lendingToken != address(0), "Invalid lending token");
        require(_collateralToken != address(0), "Invalid collateral token");
        
        lendingToken = IERC20(_lendingToken);
        collateralToken = IERC20(_collateralToken);
    }

    /**
     * @notice Deposit lending tokens into the pool
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalLiquidity += amount;
        
        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw deposited tokens from the pool
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(deposits[msg.sender] >= amount, "Insufficient deposit balance");
        require(totalLiquidity >= amount, "Insufficient pool liquidity");
        
        deposits[msg.sender] -= amount;
        totalLiquidity -= amount;
        lendingToken.safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Borrow tokens by providing collateral
     * @param collateralAmount Amount of collateral to lock
     * @param borrowAmount Amount of tokens to borrow
     * @return loanId The ID of the created loan
     */
    function borrow(uint256 collateralAmount, uint256 borrowAmount) external nonReentrant returns (uint256) {
        require(collateralAmount > 0, "Collateral must be greater than 0");
        require(borrowAmount > 0, "Borrow amount must be greater than 0");
        require(borrowAmount <= totalLiquidity, "Insufficient pool liquidity");
        
        // Calculate maximum borrowable amount based on collateral
        uint256 collateralValue = (collateralAmount * collateralTokenPrice) / 1e18;
        uint256 maxBorrowValue = (collateralValue * loanToValueRatio) / 1e18;
        uint256 maxBorrowAmount = (maxBorrowValue * 1e18) / lendingTokenPrice;
        
        require(borrowAmount <= maxBorrowAmount, "Exceeds borrowing capacity");
        
        // Transfer collateral from borrower
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);
        
        // Create loan
        uint256 loanId = nextLoanId++;
        loans[loanId] = Loan({
            borrower: msg.sender,
            collateralAmount: collateralAmount,
            borrowedAmount: borrowAmount,
            isActive: true
        });
        
        // Transfer borrowed tokens to borrower
        totalLiquidity -= borrowAmount;
        lendingToken.safeTransfer(msg.sender, borrowAmount);
        
        emit Borrowed(msg.sender, loanId, collateralAmount, borrowAmount);
        return loanId;
    }

    /**
     * @notice Repay a loan and retrieve collateral
     * @param loanId The ID of the loan to repay
     */
    function repay(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.isActive, "Loan is not active");
        require(msg.sender == loan.borrower, "Only borrower can repay");
        
        uint256 repayAmount = loan.borrowedAmount;
        
        // Transfer repayment from borrower
        lendingToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        
        // Close loan and return collateral
        loan.isActive = false;
        totalLiquidity += repayAmount;
        collateralToken.safeTransfer(loan.borrower, loan.collateralAmount);
        
        emit Repaid(msg.sender, loanId, repayAmount);
    }

    /**
     * @notice Liquidate an undercollateralized loan
     * @param loanId The ID of the loan to liquidate
     */
    function liquidate(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.isActive, "Loan is not active");
        
        // Check if loan is undercollateralized
        uint256 collateralValue = (loan.collateralAmount * collateralTokenPrice) / 1e18;
        uint256 maxBorrowValue = (collateralValue * loanToValueRatio) / 1e18;
        uint256 currentBorrowValue = (loan.borrowedAmount * lendingTokenPrice) / 1e18;
        
        require(currentBorrowValue > maxBorrowValue, "Loan is healthy");
        
        // Liquidator repays the debt
        lendingToken.safeTransferFrom(msg.sender, address(this), loan.borrowedAmount);
        
        // Close loan and transfer collateral to liquidator
        loan.isActive = false;
        totalLiquidity += loan.borrowedAmount;
        collateralToken.safeTransfer(msg.sender, loan.collateralAmount);
        
        emit Liquidated(msg.sender, loanId, loan.collateralAmount);
    }

    /**
     * @notice Update token prices (only owner)
     * @param _lendingTokenPrice New price for lending token
     * @param _collateralTokenPrice New price for collateral token
     */
    function updatePrices(uint256 _lendingTokenPrice, uint256 _collateralTokenPrice) external onlyOwner {
        require(_lendingTokenPrice > 0, "Invalid lending token price");
        require(_collateralTokenPrice > 0, "Invalid collateral token price");
        
        lendingTokenPrice = _lendingTokenPrice;
        collateralTokenPrice = _collateralTokenPrice;
    }

    /**
     * @notice Update loan-to-value ratio (only owner)
     * @param _loanToValueRatio New LTV ratio (must be <= 1e18)
     */
    function updateLoanToValueRatio(uint256 _loanToValueRatio) external onlyOwner {
        require(_loanToValueRatio <= 1e18, "LTV ratio cannot exceed 100%");
        loanToValueRatio = _loanToValueRatio;
    }

    /**
     * @notice Get loan details
     * @param loanId The ID of the loan
     * @return Loan details
     */
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        return loans[loanId];
    }
}
