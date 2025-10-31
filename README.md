# OpenZeppelin Lending & Borrowing Assignment

This repository contains a minimal OpenZeppelin-based lending/borrowing smart contract and tests for an assignment submission.

What you'll find here:

- `contracts/LendingPool.sol` — simple lending pool using OpenZeppelin's SafeERC20, Ownable, and ReentrancyGuard. Supports deposit, borrow (with collateral), repay, and liquidation.
- `contracts/MockERC20.sol` — mintable ERC20 used in tests and local deployments.
- `test/LendingPool.test.js` — Hardhat tests covering deposit/borrow/repay and liquidation scenarios.
- `scripts/deploy.js` — simple deploy script for local testing.
- `hardhat.config.js`, `package.json` — project config and dependencies.

Quick setup (Windows / PowerShell):

```powershell
# 1) Install dependencies
npm install

# 2) Compile
npm run compile

# 3) Run tests
npm test
```

Notes
- This project is intentionally minimal for assignment submission and educational purposes. It omits production-grade features such as interest accrual, sharing of pool tokens, access controls for lenders, multi-asset pricing oracles, and safety audits.
- The `LendingPool` uses a very simple admin-set price mechanism for tests. In production you'd use a decentralized price oracle (Chainlink) and robust liquidation incentives.

Submission
- This repository is prepared for submission. Ensure you include this folder when uploading to OpenZeppelin's assignment portal or wherever the instructor requests.

If you want, I can now run `npm install` and execute the tests locally and report the results.