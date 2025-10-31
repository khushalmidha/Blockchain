require("@nomiclabs/hardhat-ethers");
require("@nomicfoundation/hardhat-chai-matchers");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.19"
      }
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test"
  }
};
