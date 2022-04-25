const fs = require('fs');

const { expect } = require("chai");
const { ethers } = require("hardhat");

const _1e02 = 10n **  2n;
const _1e18 = 10n ** 18n;
const _1e20 = 10n ** 20n;

const WINDOW_SIZE = 12 * 3600;
const GRANULARITY = 24;
const PERIOD_SIZE = 30 * 60;

describe("UniSwapV2Oracle", function () {

  let owner, alice, bob;
  let wBCH, fUSD, xUSD, yUSD;
  let SwapFactory, SwapPair;
  let fusdPair, xusdPair, yusdPair;
  let Oracle;

  before(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    fUSD = await TestERC20.deploy("fUSD", 10000000n * _1e02,  2);
    xUSD = await TestERC20.deploy("xUSD", 10000000n * _1e18, 18);
    yUSD = await TestERC20.deploy("yUSD", 10000000n * _1e20, 20);
    wBCH = await TestERC20.deploy("wBCH", 10000000n * _1e18, 18);
    console.log('wBCH:', wBCH.address);
    console.log('fUSD:', fUSD.address);
    console.log('xUSD:', xUSD.address);
    console.log('yUSD:', yUSD.address);

    Oracle = await ethers.getContractFactory("UniSwapV2Oracle");
    SwapFactory = loadContractFactory('node_modules/@uniswap/v2-core/build/UniswapV2Factory.json', owner);
    SwapPair = loadContractFactory('node_modules/@uniswap/v2-core/build/UniswapV2Pair.json', owner);
  });

  beforeEach(async function () {
    const factory = await SwapFactory.deploy(owner.address);
    await factory.createPair(fUSD.address, wBCH.address);
    await factory.createPair(xUSD.address, wBCH.address);
    await factory.createPair(yUSD.address, wBCH.address);
    const fusdPairAddr = await factory.getPair(wBCH.address, fUSD.address);
    const xusdPairAddr = await factory.getPair(wBCH.address, xUSD.address);
    const yusdPairAddr = await factory.getPair(wBCH.address, yUSD.address);

    fusdPair = SwapPair.attach(fusdPairAddr);
    xusdPair = SwapPair.attach(xusdPairAddr);
    yusdPair = SwapPair.attach(yusdPairAddr);
    await addLiquidity(fusdPair, wBCH, fUSD, _1e18,      600n * _1e02     , owner);
    await addLiquidity(xusdPair, wBCH, xUSD, _1e18 * 2n, 500n * _1e18 * 2n, owner);
    await addLiquidity(yusdPair, wBCH, yUSD, _1e18 * 3n, 400n * _1e20 * 3n, owner);
  });

  it("deploy oracle", async () => {
    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();
    expect(await getPairAddrs(oracle)).to.deep.equal(pairs);
    // console.log(JSON.stringify(await getPairs(oracle), null, 2));
    console.table(await getPairs(oracle));

    // wait oracle to be ready
    for (let i = 1; i < GRANULARITY; i++) {
      await expect(oracle.getPrice()).to.be.revertedWith('Oracle: NOT_READY');
      await skipTime(PERIOD_SIZE);
      // console.log(`update#${i}`);
      await oracle.connect(alice).update();
    }
    // console.log(JSON.stringify(await getPairs(oracle), null, 2));
    await oracle.getPrice(); // ok

    // check prices
    expect(await viewPriceOfPair(oracle, 0)).to.deep.equal([ '600.00', '1.00' ]);
    expect(await viewPriceOfPair(oracle, 1)).to.deep.equal([ '500.00', '2.00' ]);
    expect(await viewPriceOfPair(oracle, 2)).to.deep.equal([ '400.00', '3.00' ]);
    expect(await viewPrice(oracle)).to.equal('466.67'); // (600*1 + 500*2 + 400*3)/6
  });

  it("moving averages", async () => {
    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();

    for (let i = 0; i < GRANULARITY; i++) {
      await skipTime(PERIOD_SIZE);
      await addLiquidity(xusdPair, wBCH, xUSD, _1e18, (500n + 10n * BigInt(i + 1)) * _1e18, owner);
      await oracle.connect(alice).update();
    }
    await oracle.getPrice(); // ok

    // check prices
    // console.log(JSON.stringify(await getPairs(oracle), null, 2));
    expect(await viewPriceOfPair(oracle, 0)).to.deep.equal([ '600.00', '1.00' ]);
    expect(await viewPriceOfPair(oracle, 1)).to.deep.equal([ '556.01', '3.00' ]);
    expect(await viewPriceOfPair(oracle, 2)).to.deep.equal([ '400.00', '3.00' ]);
    expect(await viewPrice(oracle)).to.equal('495.43'); // (600*1 + 556*3 + 400*3)/7
  });

  it("update once per epoch", async () => {
    // goto start of next epoch to make test more robust
    const timestamp = await getTime();
    const epochPeriod = Math.floor(timestamp / PERIOD_SIZE);
    const nextEpoch = (epochPeriod + 1) % GRANULARITY;
    const nextEpochTime = (epochPeriod + 1) * PERIOD_SIZE;
    await skipTime(nextEpochTime - timestamp);

    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();

    const epoch = await getEpoch();
    const lastUpdatedTime = await oracle.getLastUpdatedTime();
    await skipTime(PERIOD_SIZE/3);
    await oracle.update();
    expect(await oracle.getLastUpdatedTime()).to.equal(lastUpdatedTime);

    await skipTime(PERIOD_SIZE/3);
    await oracle.update();
    expect(await oracle.getLastUpdatedTime()).to.equal(lastUpdatedTime);

    await skipTime(PERIOD_SIZE/3 + 1);
    await oracle.update();
    expect(await oracle.getLastUpdatedTime()).to.gt(lastUpdatedTime);
    // console.log(JSON.stringify(await getPairs(oracle), null, 2));
  });

  it("update by contracts", async () => {
    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();

    const TestUpdater = await ethers.getContractFactory("TestUpdater");
    const updater = await TestUpdater.deploy(oracle.address);
    await updater.deployed();

    await expect(updater.update()).to.be.revertedWith('Oracle: NOT_EOA');
    await expect(updater.updateReserveOfPair(1)).to.be.revertedWith('Oracle: NOT_EOA');
  });

  it("update reserve of pair", async () => {
    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();

    const epoch = await getEpoch();
    expect(await getWbchReserve(oracle, 1, epoch)).to.eq('2.00');

    await addLiquidity(xusdPair, wBCH, xUSD, _1e18, 500n * _1e18, owner);
    await oracle.connect(alice).updateReserveOfPair(1);
    expect(await getWbchReserve(oracle, 1, epoch)).to.eq('2.00');

    await removeHalfLiquidity(xusdPair, owner);
    await oracle.connect(alice).updateReserveOfPair(1);
    expect(await getWbchReserve(oracle, 1, epoch)).to.eq('1.50');

    await expect(oracle.connect(alice).updateReserveOfPair(3))
      .to.be.revertedWith('Oracle: INVALID_PAIR_IDX');
  });

  it("missing observations", async () => {
    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();

    for (let i = 1; i < GRANULARITY; i++) {
      await skipTime(PERIOD_SIZE);
      await oracle.connect(alice).update();
    }
    await oracle.getPrice(); // ok

    await skipTime(PERIOD_SIZE);
    for (let i = 1; i < GRANULARITY; i++) {
      await skipTime(PERIOD_SIZE);
      await oracle.connect(alice).update();
    }
    await expect(oracle.getPrice())
      .to.be.revertedWith('Oracle: MISSING_HISTORICAL_OBSERVATION');

    await skipTime(PERIOD_SIZE);
    await oracle.connect(alice).update();
    await oracle.getPrice(); // ok
  });

  it("events", async () => {
    const pairs = [fusdPair.address, xusdPair.address, yusdPair.address];
    const oracle = await Oracle.deploy(wBCH.address, pairs);
    await oracle.deployed();

    for (let i = 1; i < GRANULARITY; i++) {
      await skipTime(PERIOD_SIZE);
      await oracle.connect(alice).update();
    }
    await oracle.getPrice(); // ok

    await skipTime(PERIOD_SIZE);
    await expect(oracle.connect(alice).update())
        .to.emit(oracle, 'UpdateObservations');
        // .withArgs(alice.address, '466666666666666666666', await getTime());

    await removeHalfLiquidity(xusdPair, owner);
    await expect(oracle.connect(alice).updateReserveOfPair(1))
        .to.emit(oracle, 'UpdateWbchReserve');
        // .withArgs(alice.address, 1, '1000000000000000023', await getTime());
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
async function removeHalfLiquidity(pair, owner) {
  const bal = await pair.balanceOf(owner.address);
  const balHalf = bal.div(ethers.BigNumber.from(2));
  await pair.transfer(pair.address, balHalf);
  await pair.burn(owner.address);
}

async function viewPrice(oracle) {
  return bn18ToNum(await oracle.avgPrice()).toFixed(2);
}
async function viewPriceOfPair(oracle, pairIdx) {
  const [price, weight] = await oracle.getPriceOfPair(pairIdx);
  return [
    bn18ToNum(price).toFixed(2),
    bn18ToNum(weight).toFixed(2),
  ];
}

async function getWbchReserve(oracle, pairIdx, epoch) {
  const pairs = await getPairs(oracle);
  return pairs[pairIdx].observations[epoch].r.toFixed(2);
}
async function getPairs(oracle) {
  const pairs = await oracle.getPairs();
  return pairs.map(p => ({
    addr: p.addr,
    wbchIdx: p.wbchIdx,
    usdDecimals: p.usdDecimals,
    observations: p.observations.map(o => ({
      t: Number(o.timestamp),
      p: o.priceCumulative.toHexString(),
      r: bn18ToNum(o.wbchReserve),
    })),
  }));
}

async function getPairAddrs(oracle) {
  const pairs = await oracle.getPairs();
  return pairs.map(p => p.addr);
}

async function getEpoch() {
  const timestamp = await getTime();
  const epochPeriod = Math.floor(timestamp / PERIOD_SIZE);
  return epochPeriod % GRANULARITY;
}
async function getTime() {
  return (await ethers.provider.getBlock('latest')).timestamp;
}
async function skipTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine");
}

function bn18ToNum(n) {
  return Number(ethers.utils.formatUnits(n));
}
