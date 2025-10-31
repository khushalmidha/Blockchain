const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LendingPool", function () {
  let owner, alice, bob, liquidator;
  let Asset, Collateral, asset, collateral, Pool;

  beforeEach(async function () {
    [owner, alice, bob, liquidator] = await ethers.getSigners();

    Asset = await ethers.getContractFactory("MockERC20");
    asset = await Asset.deploy("Mock DAI", "mDAI");
    await asset.deployed();

    Collateral = await ethers.getContractFactory("MockERC20");
    collateral = await Collateral.deploy("Mock WETH", "mWETH");
    await collateral.deployed();

    Pool = await ethers.getContractFactory("LendingPool");
    pool = await Pool.deploy(asset.address, collateral.address);
    await pool.deployed();

    // owner mints large supply for testing
    await asset.mint(owner.address, ethers.utils.parseEther("1000000"));
    await collateral.mint(owner.address, ethers.utils.parseEther("1000000"));

    // Distribute to users
    await asset.transfer(alice.address, ethers.utils.parseEther("1000"));
    await collateral.transfer(bob.address, ethers.utils.parseEther("1000"));

    // owner deposits liquidity into pool
    await asset.connect(owner).approve(pool.address, ethers.utils.parseEther("1000000"));
    await pool.connect(owner).deposit(ethers.utils.parseEther("1000"));
  });

  it("allows deposit and borrow, then repay and return collateral", async function () {
    // Bob approves collateral and borrows
    await collateral.connect(bob).approve(pool.address, ethers.utils.parseEther("10"));

    // Bob borrows: with default prices 1:1 and LTV 50%, collateral 10 -> max borrow = 5
    const tx = await pool.connect(bob).borrow(ethers.utils.parseEther("10"), ethers.utils.parseEther("5"));
    const receipt = await tx.wait();

    // loanId should be emitted; check bob asset balance increased
    const bobAssetBal = await asset.balanceOf(bob.address);
    expect(bobAssetBal).to.equal(ethers.utils.parseEther("5"));

    // repay fully
    await asset.connect(bob).approve(pool.address, ethers.utils.parseEther("5"));
    // find loanId from event
    const event = receipt.events.find((e) => e.event === "Borrow");
    const loanId = event.args[1];

    await pool.connect(bob).repay(loanId, ethers.utils.parseEther("5"));

    // after repay, bob should have original collateral back
    const bobCollateral = await collateral.balanceOf(bob.address);
    expect(bobCollateral).to.equal(ethers.utils.parseEther("1000"));
  });

  it("allows liquidation when undercollateralized", async function () {
    // Bob deposits collateral and borrows max allowed (10 collateral -> 5 asset)
    await collateral.connect(bob).approve(pool.address, ethers.utils.parseEther("10"));
    const tx = await pool.connect(bob).borrow(ethers.utils.parseEther("10"), ethers.utils.parseEther("5"));
    const receipt = await tx.wait();
    const event = receipt.events.find((e) => e.event === "Borrow");
    const loanId = event.args[1];

    // Now simulate price drop of collateral to 0.2 (20% of previous). Owner sets prices.
    await pool.connect(owner).setPrices(ethers.utils.parseEther("1"), ethers.utils.parseEther("0.2"));

    // Liquidator needs asset to repay
    await asset.mint(liquidator.address, ethers.utils.parseEther("10"));
    await asset.connect(liquidator).approve(pool.address, ethers.utils.parseEther("10"));

    await pool.connect(liquidator).liquidate(loanId);

    // loan should be closed
    const loan = await pool.loans(loanId);
    expect(loan.open).to.equal(false);
  });
});
