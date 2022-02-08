const hre = require("hardhat");

const priceOracleAddr = '0x';
const priceOracleABI = [
  `function getPrice() external returns (uint)`,
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
  console.log('price:', price);
}
