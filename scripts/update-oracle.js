import { ethers } from "ethers";

const WINDOW_SIZE = 12 * 3600;
const PERIOD_SIZE = 30 * 60;

const priceOracleAddr = '0xa1b0C0158b8602de44A291B563FAd733baE10Eeb';
const priceOracleABI = [
  `function update() public`,
  `function getLastUpdatedTime() public view returns (uint64)`,
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

  while (true) {
    console.log('now:', new Date());

    const now = Math.floor(Date.now() / 1000);
    const price = await oracle.getPrice();
    const lastUpdatedTime = await oracle.getLastUpdatedTime();
    console.log('price:', ethers.utils.formatUnits(price));
    console.log('lastUpdatedTime:', new Date(lastUpdatedTime * 1000));

    const epochStartTime = Math.floor(now / PERIOD_SIZE) * PERIOD_SIZE;

    if (now - epochStartTime > PERIOD_SIZE / 2) {
      const tx = await oracle.update();
      console.log('tx:', tx);

      const receipt = await tx.wait();
      console.log('receipt:', receipt);
    }

    await sleep(60 * 1000);
  }
}

export function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
