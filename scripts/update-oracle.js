const fs = require("fs");
const ethers = require("ethers");
const prompt = require('password-prompt');
const { decrypt } = require('./mycrypto');

const WINDOW_SIZE = 12 * 3600;
const PERIOD_SIZE = 30 * 60;

const priceOracleAddr = '0xa1b0C0158b8602de44A291B563FAd733baE10Eeb'; // TODO
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

/*
  PRIV_KEY_FILE=pato/to/priv_key_file \
  SBCH_RPC_URL=http://13.214.157.111:8545 \
  node update-oracle.js
*/
async function main() {
  const signer = await getSigner();
  const oracle = new ethers.Contract(priceOracleAddr, priceOracleABI, signer);

  while (true) {
    console.log('tick:', new Date());

    try {
      await tryToUpdateOracle(oracle);
    } catch (err) {
      console.log('failed to update oracle:', err);
    }

    await sleep(60 * 1000);
  }
}

async function getSigner() {
  let signer, provider;
  if (process.env.PRIV_KEY_FILE) {
    const sbchRpcURL = process.env.SBCH_RPC_URL || 'http://localhost:8545';
    const cipherKey = fs.readFileSync(process.env.PRIV_KEY_FILE).toString().trim();
    const password = await prompt('password: ', {method:'hide'});
    const privKey = await decrypt(cipherKey, password);
    console.log('rpc url:', sbchRpcURL);
    provider = new ethers.providers.JsonRpcProvider(sbchRpcURL);
    signer = new ethers.Wallet(privKey, provider);
  } else {
    [signer] = await ethers.getSigners();
    provider = signer.provider;
  }
  return signer;
}

async function tryToUpdateOracle(oracle) {
  const provider = oracle.signer.provider
  const height = await provider.getBlockNumber()
  const blk = await provider.getBlock(height)
  const now = blk.timestamp
  const price = await oracle.getPrice();
  const lastUpdatedTime = await oracle.getLastUpdatedTime();
  console.log('now:', new Date(now * 1000));
  console.log('price:', ethers.utils.formatUnits(price));
  console.log('lastUpdatedTime:', new Date(lastUpdatedTime * 1000));

  if (now - lastUpdatedTime < PERIOD_SIZE) {
    console.logg('oracle is up-to-date');
  } else {
    console.log('updating oracle ...');
    const tx = await oracle.update();
    console.log('tx:', tx);

    const receipt = await tx.wait();
    console.log('receipt:', receipt);
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
