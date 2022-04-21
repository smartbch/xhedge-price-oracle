const hre = require("hardhat");

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

async function main() {
  const [signer] = await ethers.getSigners();
  console.log('address:', signer.address);
  console.log('balance:', ethers.utils.formatUnits(await signer.provider.getBalance(signer.address)));

  const FixedOracle = await hre.ethers.getContractFactory("FixedOracle");
  const fixedOracle = await FixedOracle.deploy();
  await fixedOracle.deployed();
  console.log("FixedOracle deployed to:", fixedOracle.address);
  // 0xa1b0C0158b8602de44A291B563FAd733baE10Eeb
}
