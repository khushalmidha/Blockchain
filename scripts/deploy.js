async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const asset = await MockERC20.deploy("Mock DAI", "mDAI");
  await asset.deployed();
  const collateral = await MockERC20.deploy("Mock WETH", "mWETH");
  await collateral.deployed();

  const LendingPool = await ethers.getContractFactory("LendingPool");
  const pool = await LendingPool.deploy(asset.address, collateral.address);
  await pool.deployed();

  console.log("Asset:", asset.address);
  console.log("Collateral:", collateral.address);
  console.log("LendingPool:", pool.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
