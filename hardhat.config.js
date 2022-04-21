require("@nomiclabs/hardhat-waffle");
require("@atixlabs/hardhat-time-n-mine");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const KEY = process.env.KEY || '0x1234';
// console.log('KEY:', KEY);

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    sbch_mainnet: {
      url: 'http://13.213.50.64:8545',
      accounts: [KEY],
      gasPrice: 1050000000,
    },
  },
};
