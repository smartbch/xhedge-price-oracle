const hre = require("hardhat");

const erc20ABI = [
  `function name() public view returns (string)`,
  `function symbol() public view returns (string)`,
  `function decimals() public view returns (uint8)`,
];
const swapPairABI = [
  `function symbol() public view returns (string)`,
  `function token0() external view returns (address)`,
  `function token1() external view returns (address)`,
  `function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)`,
];

const WBCH_ADDR                  = '0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04';
const FLEXUSD_ADDR               = '0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72';
const BENSWAP_WBCH_FLEXUSD_ADDR  = '0x65C042E455a6B84132c78E8FDaE058188e17c75A';
const MISTSWAP_WBCH_FLEXUSD_ADDR = '0x24f011f12Ea45AfaDb1D4245bA15dCAB38B43D13';
const COWSWAP_WBCH_FLEXUSD_ADDR  = '0x337dFDea133F6D50f6442e2BF007D18056084224';
const TANGOWAP_WBCH_FLEXUSD_ADDR = '0xA15F8102AB4723A4D1554363c0c8AFF471F16E21';
const TROPICAL_WBCH_FLEXUSD_ADDR = '0xbC6ade4d6b3aEFe107C37C5C028De1E247de4533';

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

  const pairs = [
    BENSWAP_WBCH_FLEXUSD_ADDR,
    MISTSWAP_WBCH_FLEXUSD_ADDR,
    COWSWAP_WBCH_FLEXUSD_ADDR,
    TANGOWAP_WBCH_FLEXUSD_ADDR,
    TROPICAL_WBCH_FLEXUSD_ADDR,
  ]
  const pairsInfo = await queryPairs(pairs, signer);
  console.table(pairsInfo);

  const UniswapV2Oracle = await ethers.getContractFactory("UniswapV2Oracle");
  const uniswapV2Oracle = await UniswapV2Oracle.deploy(WBCH_ADDR, pairs);
  await uniswapV2Oracle.deployed();
  console.log("UniswapV2Oracle deployed to:", uniswapV2Oracle.address);
}

/*
┌─────────┬───────────────┬──────────────────────────────────────────────┬──────────────────────────────────────────────┬──────────────────────────────────────────────┬───────────┬──────────────┐
│ (index) │    symbol     │                     addr                     │                    token0                    │                    token1                    │ reserve0  │   reserve1   │
├─────────┼───────────────┼──────────────────────────────────────────────┼──────────────────────────────────────────────┼──────────────────────────────────────────────┼───────────┼──────────────┤
│    0    │ 'BenSwap-LP'  │ '0x65C042E455a6B84132c78E8FDaE058188e17c75A' │ '0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04' │ '0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72' │ '1112.16' │ '339972.86'  │
│    1    │     'MLP'     │ '0x24f011f12Ea45AfaDb1D4245bA15dCAB38B43D13' │ '0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04' │ '0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72' │ '8235.16' │ '2517811.67' │
│    2    │  'Muesli-LP'  │ '0x337dFDea133F6D50f6442e2BF007D18056084224' │ '0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04' │ '0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72' │ '131.24'  │  '40035.61'  │
│    3    │     'TLP'     │ '0xA15F8102AB4723A4D1554363c0c8AFF471F16E21' │ '0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04' │ '0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72' │ '3835.40' │ '1172101.64' │
│    4    │ 'Tropical-LP' │ '0xbC6ade4d6b3aEFe107C37C5C028De1E247de4533' │ '0x3743eC0673453E5009310C727Ba4eaF7b3a1cc04' │ '0x7b2B3C5308ab5b2a1d9a94d20D35CCDf61e05b72' │ '181.81'  │  '55580.44'  │
└─────────┴───────────────┴──────────────────────────────────────────────┴──────────────────────────────────────────────┴──────────────────────────────────────────────┴───────────┴──────────────┘
*/
async function queryPairs(pairs, signer) {
  const pairsInfo = [];

  for (const pairAddr of pairs) {
    const swapPair = new ethers.Contract(pairAddr, swapPairABI, signer);
    const symbol = await swapPair.symbol();
    const token0 = await swapPair.token0();
    const token1 = await swapPair.token1();
    const [reserve0, reserve1] = await swapPair.getReserves();
    console.log('pair:', pairAddr);
    // console.log('token0:', ethers.utils.formatUnits(token0));
    // console.log('token1:', ethers.utils.formatUnits(token1));
    // console.log('reserve0:', ethers.utils.formatUnits(reserve0));
    // console.log('reserve1:', ethers.utils.formatUnits(reserve1));
    pairsInfo.push({
      symbol  : symbol,
      addr    : pairAddr,
      token0  : token0,
      token1  : token1,
      reserve0: Number(ethers.utils.formatUnits(reserve0)).toFixed(2),
      reserve1: Number(ethers.utils.formatUnits(reserve1)).toFixed(2),
    });
  }

  return pairsInfo;
}
