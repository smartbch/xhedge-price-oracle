const fs = require('fs');

const { expect } = require("chai");
const { ethers } = require("hardhat");

const _1e10 = 10n ** 10n;
const _1e18 = 10n ** 18n;
const _1e20 = 10n ** 20n;

describe("UniSwapV2Oracle", function () {

  let owner, alice, bob;
  let wBCH, fUSD, xUSD;
  let SwapFactory, SwapPair;
  let fusdPair, xusdPair, yusdPair;
  let Oracle;

  before(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    wBCH = await TestERC20.deploy("wBCH", 10000000n * _1e18, 18);
    fUSD = await TestERC20.deploy("fUSD", 10000000n * _1e18, 18);
    xUSD = await TestERC20.deploy("xUSD", 10000000n * _1e10, 10);
    yUSD = await TestERC20.deploy("yUSD", 10000000n * _1e20, 20);

    Oracle = await ethers.getContractFactory("UniSwapV2Oracle");
    SwapFactory = loadContractFactory('node_modules/@uniswap/v2-core/build/UniswapV2Factory.json', owner);
    SwapPair = loadContractFactory('node_modules/@uniswap/v2-core/build/UniswapV2Pair.json', owner);
  });

  beforeEach(async function () {
    const factory = await SwapFactory.deploy(owner.address);
    await factory.createPair(wBCH.address, fUSD.address);
    await factory.createPair(xUSD.address, wBCH.address);
    await factory.createPair(yUSD.address, wBCH.address);
    const fusdPairAddr = await factory.getPair(wBCH.address, fUSD.address);
    const xusdPairAddr = await factory.getPair(wBCH.address, xUSD.address);
    const yusdPairAddr = await factory.getPair(wBCH.address, yUSD.address);

    fusdPair = SwapPair.attach(fusdPairAddr);
    xusdPair = SwapPair.attach(xusdPairAddr);
    yusdPair = SwapPair.attach(yusdPairAddr);
    await addLiquidity(fusdPair, wBCH, fUSD, _1e18, 60000n * _1e18, owner);
    await addLiquidity(xusdPair, wBCH, xUSD, _1e18, 60000n * _1e10, owner);
    await addLiquidity(yusdPair, wBCH, yUSD, _1e20, 60000n * _1e20, owner);
  });

  it("deploy oracles", async function () {
    const oracle0 = await Oracle.deploy(wBCH.address, []);
    await oracle0.deployed();
    expect(await getTrackedPairs(oracle0)).to.deep.equal([]);

    const oracle1 = await Oracle.deploy(wBCH.address, [fusdPair.address]);
    await oracle1.deployed();
    expect(await getTrackedPairs(oracle1)).to.deep.equal([fusdPair.address]);

    const oracle2 = await Oracle.deploy(wBCH.address, [yusdPair.address, xusdPair.address]);
    await oracle2.deployed();
    expect(await getTrackedPairs(oracle2)).to.deep.equal([yusdPair.address, xusdPair.address]);
  });

  it("add/remove pairs", async function () {
    const oracle = await Oracle.deploy(wBCH.address, []);
    await oracle.deployed();

    await oracle.addPair(fusdPair.address);
    await oracle.addPair(xusdPair.address);
    await oracle.addPair(yusdPair.address);
    expect(await getTrackedPairs(oracle)).to.deep.equal(
      [fusdPair.address, xusdPair.address, yusdPair.address]);

    await oracle.removePair(xusdPair.address);
    expect(await getTrackedPairs(oracle)).to.deep.equal(
      [fusdPair.address, yusdPair.address]);

    await oracle.addPair(xusdPair.address);
    expect(await getTrackedPairs(oracle)).to.deep.equal(
      [fusdPair.address, yusdPair.address, xusdPair.address]);

    await oracle.removePair(fusdPair.address);
    expect(await getTrackedPairs(oracle)).to.deep.equal(
      [xusdPair.address, yusdPair.address]);
  });

  it("add/remove pairs: not owner!", async function () {
    const oracle = await Oracle.deploy(wBCH.address, [xusdPair.address, yusdPair.address]);
    await oracle.deployed();

    await expect(oracle.connect(alice).addPair(yusdPair.address)).to.be
      .revertedWith('Ownable: caller is not the owner');
    await expect(oracle.connect(alice).addPair(yusdPair.address)).to.be
      .revertedWith('Ownable: caller is not the owner');
  });

  // it("get price", async function () {
  //   // await addLiquidity(fusdPair, wBCH, fUSD, _1e18, 60000n * _1e18, owner);
  //   const oracle = await Oracle.deploy(wBCH.address, [fusdPair.address]);
  //   await oracle.deployed();
  //   await oracle.getPrice();

  //   // await printInfo(fusdPair);
  //   expect(await oracle.callStatic.getPrice()).to.equal(60000n * _1e18);
  // });

  // it("get price: currentCumulativePrice", async function () {
  //   const oracle = await Oracle.deploy(wBCH.address, [fusdPair.address]);
  //   await oracle.deployed();
  //   await oracle.getPrice();
  //   expect(await oracle.callStatic.getPrice()).to.equal(60000n * _1e18);

  //   await addLiquidity(fusdPair, wBCH, fUSD, _1e18, 58000n * _1e18, owner);
  //   await oracle.getPrice();
  //   expect(await oracle.callStatic.getPrice()).to.equal(59800n * _1e18);

  //   await addLiquidity(fusdPair, wBCH, fUSD, _1e18, 56000n * _1e18, owner);
  //   await oracle.getPrice();
  //   expect(await oracle.callStatic.getPrice()).to.equal(59333333333333333333333n);

  //   timeAndMine.increaseTime(100);
  //   await oracle.getPrice();
  //   expect(await oracle.callStatic.getPrice()).to.equal(58110091743119266055045n);
  // });

  // it("getPriceWithoutUpdate: currentCumulativePrice", async function () {
  //   const oracle = await Oracle.deploy(wBCH.address, [fusdPair.address]);
  //   await oracle.deployed();
  //   await oracle.update();
  //   expect(await oracle.getPriceWithoutUpdate()).to.equal(60000n * _1e18);

  //   await addLiquidity(fusdPair, wBCH, fUSD, _1e18, 58000n * _1e18, owner);
  //   await oracle.getPrice();
  //   expect(await oracle.getPriceWithoutUpdate()).to.equal(59800n * _1e18);

  //   await addLiquidity(fusdPair, wBCH, fUSD, _1e18, 56000n * _1e18, owner);
  //   await oracle.getPrice();
  //   expect(await oracle.getPriceWithoutUpdate()).to.equal(59333333333333333333333n);

  //   // timeAndMine.increaseTime(100);
  //   // await oracle.getPrice();
  //   // expect(await oracle.getPriceWithoutUpdate()).to.equal(58110091743119266055045n);
  // });

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
  await pair.sync();
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
