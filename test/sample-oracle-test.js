const fs = require('fs');

const { expect } = require("chai");
const { ethers } = require("hardhat");

const _1e18 = 10n ** 18n;

describe("UniSwapV2OracleSimple", function () {

  let owner, alice, bob;
  let wBCH, flexUSD, sBUSD;
  let flexPair, busdPair;
  let Oracle;

  before(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    wBCH = await TestERC20.deploy("wBCH", 10000000n * _1e18, 18);
    flexUSD = await TestERC20.deploy("flexUSD", 10000000n * _1e18, 18);
    sBUSD = await TestERC20.deploy("sBUSD", 10000000 * 100, 2);

    const SwapFactory = loadContractFactory('node_modules/@uniswap/v2-core/build/UniswapV2Factory.json', owner);
    const factory = await SwapFactory.deploy(owner.address);
    await factory.createPair(wBCH.address, flexUSD.address);
    await factory.createPair(sBUSD.address, wBCH.address);
    const flexPairAddr = await factory.getPair(wBCH.address, flexUSD.address);
    const busdPairAddr = await factory.getPair(wBCH.address, sBUSD.address);

    const SwapPair = loadContractFactory('node_modules/@uniswap/v2-core/build/UniswapV2Pair.json', owner);
    flexPair = SwapPair.attach(flexPairAddr);
    busdPair = SwapPair.attach(busdPairAddr);
    await addLiquidity(flexPair, wBCH, flexUSD, _1e18, 60000n * _1e18, owner);
    await addLiquidity(busdPair, wBCH, sBUSD,   _1e18, 60000n * 100n,  owner);

    Oracle = await ethers.getContractFactory("UniSwapV2OracleSimple");
  });

  it("deploy oracles", async function () {
    const oracle0 = await Oracle.deploy(wBCH.address, []);
    await oracle0.deployed();
    expect(await getTrackedPairs(oracle0)).to.deep.equal([]);

    const oracle1 = await Oracle.deploy(wBCH.address, [flexPair.address]);
    await oracle1.deployed();
    expect(await getTrackedPairs(oracle1)).to.deep.equal([flexPair.address]);

    const oracle2 = await Oracle.deploy(wBCH.address, [flexPair.address, busdPair.address]);
    await oracle2.deployed();
    expect(await getTrackedPairs(oracle2)).to.deep.equal([flexPair.address, busdPair.address]);
  });

  it("add/remove pairs", async function () {
    const oracle = await Oracle.deploy(wBCH.address, []);
    await oracle.deployed();

    await oracle.addPair(flexPair.address);
    await oracle.addPair(flexPair.address);
    await oracle.addPair(busdPair.address);
    await oracle.addPair(flexPair.address);
    await oracle.addPair(flexPair.address);
    expect(await getTrackedPairs(oracle)).to.deep.equal(
      [flexPair.address, flexPair.address, busdPair.address, flexPair.address, flexPair.address]);

    await oracle.removePair(busdPair.address);
    expect(await getTrackedPairs(oracle)).to.deep.equal(
      [flexPair.address, flexPair.address, flexPair.address, flexPair.address]);
  });

  it("get price", async function () {
    await addLiquidity(flexPair, wBCH, flexUSD, _1e18, 60000n * _1e18, owner);
    const oracle = await Oracle.deploy(wBCH.address, [flexPair.address]);
    await oracle.deployed();
    await oracle.getPrice();

    // await printInfo(flexPair);
    expect(await oracle.callStatic.getPrice()).to.equal(60000n * _1e18);
  });

});

function loadContractFactory(abiFile, signer) {
  return ethers.ContractFactory.fromSolidity(fs.readFileSync(abiFile, 'utf8'), signer);
}

async function addLiquidity(pair, token0, token1, amt0, amt1, owner) {
  await token0.transfer(pair.address, amt0);
  await token1.transfer(pair.address, amt1);
  await pair.mint(owner.address);
}

async function printInfo(pair) {
  let [r0, r1, ts] = await pair.getReserves();
  let p0c = await pair.price0CumulativeLast();
  let p1c = await pair.price1CumulativeLast();
  console.log('r0:', r0.toString());
  console.log('r1:', r1.toString());
  console.log('ts:', ts);
  console.log('p0c:', p0c.toString());
  console.log('p1c:', p1c.toString());
}

async function getTrackedPairs(oracle) {
  const pairs = [];
  for (let i = 0; ; i++) {
    try {
      pairs.push((await oracle.pairs(i)).addr);
    } catch (e) {
      break;
    }
  }
  return pairs;
}
