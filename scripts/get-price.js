const hre = require("hardhat");

const priceOracleAddr = '0xa1b0C0158b8602de44A291B563FAd733baE10Eeb';
const priceOracleABI = [
  `function getPrice() external view returns (uint)`,
];

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

async function main() {
  const [signer] = await ethers.getSigners();
  const provider = signer.provider;

  const oracle = new ethers.Contract(priceOracleAddr, priceOracleABI, provider);
  const price = await oracle.getPrice();
  console.log('price:', ethers.utils.formatUnits(price));
}
