import { expect } from 'chai';
import { ethers, BigNumber } from 'ethers';
import { time } from '@nomicfoundation/hardhat-network-helpers'
import { makeSuite } from './make-suite';
import { bigNumber } from '../scripts/utils';
import { waitTx } from '../scripts/utils/contracts';
import { OptionTokenInterface } from '../types/contracts/tokens/OptionToken';

makeSuite('Vault', (testEnv) => {
  before(async () => {
  });

  it("Should be able to deposit", async () => {
    const { vault, eth, lpToken, deployer } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("10000");
    await eth.mint(amount);
    await eth.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    const lockedBalance = await lpToken.lockedBalanceOf(deployer.address);
    expect(lockedBalance).to.be.equal(amount);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
  });

  it("Should not be able to withdraw immediately", async() => {
    const { vault, deployer, lpToken} = testEnv;
    if(vault == undefined || lpToken == undefined || deployer == undefined) {
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther('100');
    await expect(vault.withdraw(amount, deployer.address))
          .to.be.revertedWithCustomError(lpToken, "WithdrawMoreThanMax")
          .withArgs(lpToken.address, amount, 0);
  })

  it("Should not be able to withdraw when the release time is not reached", async() => {
    const { deployer, vault, lpToken} = testEnv;
    if(lpToken == undefined || vault == undefined || deployer == undefined) {
      throw new Error('testEnv not initialized');
    }
    const releaseTime = await lpToken.releaseTime(deployer.address);
    const blockTimestamp = await time.latest() + 1;
    await time.setNextBlockTimestamp(blockTimestamp);
    const amount = ethers.utils.parseEther('100');
    await expect(vault.withdraw(amount, deployer.address))
          .to.be.revertedWithCustomError(lpToken, "WithdrawMoreThanMax")
          .withArgs(lpToken.address, amount, 0);
  })

  it("Balance should be locked when the release time is reached but user deposie some asset before it.", async() => {
    const { vault, eth, lpToken, deployer, reserve } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || reserve === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("10000");
    expect(await lpToken.lockedBalanceOf(deployer.address)).to.be.equal(amount);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
    const releaseTime = await lpToken.releaseTime(deployer.address);
    await time.increase(24*3600);
    await eth.mint(amount);
    await eth.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    await time.increaseTo(releaseTime.toNumber());
    const lockedBalance = await lpToken.lockedBalanceOf(deployer.address);
    expect(await lpToken.lockedBalanceOf(deployer.address)).to.be.equal(lockedBalance);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
  })

  it("Locked balance should be 0 when the release time is reached", async() => {
    const { vault, eth, lpToken, deployer, reserve } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || reserve === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = await lpToken.lockedBalanceOf(deployer.address);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
    const releaseTime = await lpToken.releaseTime(deployer.address);
    await time.increaseTo(releaseTime.toNumber());
    expect(await lpToken.lockedBalanceOf(deployer.address)).to.be.equal(0);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(amount);
  })

  it("Balance should not be changed after a deposit", async() => {
    const { vault, eth, lpToken, deployer, reserve } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || reserve === undefined){
      throw new Error('testEnv not initialized');
    }
    const balance = await lpToken.balanceOf(deployer.address);
    const amount = ethers.utils.parseEther("100");
    await eth.mint(amount);
    await eth.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    expect(await lpToken.lockedBalanceOf(deployer.address)).to.be.equal(amount);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(balance);
  })

  it("Should be able to withdraw", async () => {
    const { vault, eth, lpToken, deployer, reserve } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || reserve === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("100");
    const fee = amount.mul(3).div(1000);
    await lpToken.approve(vault.address, amount);
    await vault.withdraw(amount, deployer.address);
    const balance = await eth.balanceOf(deployer.address);
    expect(balance).to.be.equal(amount.sub(fee));
    const reserveBalance = await eth.balanceOf(reserve.address);
    expect(reserveBalance).to.be.equal(fee);
  });

  it("Should not be able to withdraw all the remaining assets", async () => {
    const { vault, eth, lpToken, deployer } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = await lpToken.balanceOf(deployer.address);
    const totalAssets = await lpToken.totalAssets();
    await lpToken.approve(vault.address, amount);
    await expect(vault.withdraw(amount, deployer.address))
          .to.be.revertedWithCustomError(lpToken, "WithdrawMoreThanMax")
          .withArgs(lpToken.address, amount, totalAssets.div(2));
  });

  it("Should be able to transfer balance to another user", async () => {
    const { eth, lpToken, deployer, users } = testEnv;
    if(lpToken === undefined || eth === undefined || deployer === undefined || users === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = await lpToken.balanceOf(deployer.address);
    await lpToken.transfer(users[0].address, amount);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
    expect(await lpToken.balanceOf(users[0].address)).to.be.equal(amount);
  });

  it("Should be able to transfer balance to another user after the release time", async () => {
    const { vault, eth, lpToken, deployer, users } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || users === undefined){
      throw new Error('testEnv not initialized');
    }
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
    const lockedBalance = await lpToken.lockedBalanceOf(deployer.address);
    expect(lockedBalance).to.be.greaterThan(0);
    const amount = ethers.utils.parseEther("100");
    const user0Balance = await lpToken.balanceOf(users[0].address);
    const releaseTime = await lpToken.releaseTime(deployer.address);
    await time.increaseTo(releaseTime.toNumber());
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(lockedBalance);
    await eth.mint(amount);
    await eth.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    const newReleaseTime = await lpToken.releaseTime(deployer.address);
    expect(await lpToken.lockedBalanceOf(deployer.address)).to.be.equal(amount);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(lockedBalance);
    await time.increaseTo(newReleaseTime.toNumber());
    expect(await lpToken.lockedBalanceOf(deployer.address)).to.be.equal(0);
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(lockedBalance.add(amount));
    await lpToken.transfer(users[0].address, lockedBalance.add(amount));
    expect(await lpToken.balanceOf(deployer.address)).to.be.equal(0);
    expect(await lpToken.balanceOf(users[0].address)).to.be.equal(user0Balance.add(lockedBalance).add(amount));
  });



  it("Should be able to open a position", async () => {
    const { vault, keeperHelper, eth, lpToken, deployer, markets } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || keeperHelper === undefined || Object.keys(markets).length == 0){
      throw new Error('testEnv not initialized');
    }
    const market = markets['BAYC'];
    const nft = market.nft;
    const optionToken = market.optionToken;
    const expiry = await time.latest() + 28 * 3600 * 24;
    const strikePrice = bigNumber(12, 19);
    const amount = bigNumber(5, 17);
    const premium = (await vault.estimatePremium(nft, 0, strikePrice, expiry, amount)).mul(105).div(100);
    const openTxRec = await waitTx(
      await vault.openPosition(
        nft, 
        deployer.address, 
        0, 
        strikePrice, 
        expiry, 
        amount, premium));
    const events = openTxRec.events;
    expect(events).is.not.undefined;
    const openEvent = events[events.length - 1];
    const estimatedPremium = openEvent.args['estimatedPremium'];
    const keeperFee = await vault.KEEPER_FEE();
    expect(estimatedPremium).to.be.equal(BigNumber.from("778209470375937403").mul(amount).add(bigNumber(1,18)).sub(1).div(bigNumber(1, 18)));
    await eth.approve(vault.address, premium.add(keeperFee));
  });

  it("Keeper should be able to active a position", async() => {
    const { vault, keeperHelper, deployer, markets } = testEnv;
    if(vault === undefined || keeperHelper === undefined || deployer === undefined || Object.keys(markets).length == 0) {
      throw new Error('testEnv not initialized');
    }
    const market = markets['BAYC'];
    const nft = market.nft;
    const optionToken = market.optionToken;
    const positionIds = await keeperHelper.getPendingOptions(nft);
    let state = await optionToken.optionPositionState(positionIds[0]);
    expect(state).to.be.equal(1); // PENDING
    await keeperHelper.batchActivateOptions(nft, positionIds);
    state = await optionToken.optionPositionState(positionIds[0]);
    expect(state).to.be.equal(2); // ACTIVE
  });

  it("Should be able to open a position on behalf of other user", async () => {
    const { vault, keeperHelper, eth, lpToken, deployer, markets, users } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || keeperHelper === undefined || Object.keys(markets).length == 0 || Object.keys(users).length == 0){
      throw new Error('testEnv not initialized');
    }
    const market = markets['BAYC'];
    const nft = market.nft;
    const optionToken = market.optionToken;
    const expiry = await time.latest() + 28 * 3600 * 24;
    const strikePrice = bigNumber(12, 19);
    const amount = bigNumber(5, 17);
    const premium = (await vault.estimatePremium(nft, 0, strikePrice, expiry, amount)).mul(105).div(100);
    const receiver = users[0];
    const openTxRec = await waitTx(
      await vault.openPosition(
        nft,
        receiver.address,
        0,
        strikePrice,
        expiry,
        amount, premium));
    const events = openTxRec.events;
    expect(events).is.not.undefined;
    const openEvent = events[events.length - 1];
    const estimatedPremium = openEvent.args['estimatedPremium'];
    expect(estimatedPremium).to.be.equal(BigNumber.from("778209470375937403").mul(amount).add(bigNumber(1,18)).sub(1).div(bigNumber(1, 18)));
    await eth.approve(vault.address, premium);
    const positionIds = await keeperHelper.getPendingOptions(nft);
    let state = await optionToken.optionPositionState(positionIds[0]);
    expect(state).to.be.equal(1); // PENDING
    await keeperHelper.batchActivateOptions(nft, positionIds);
    state = await optionToken.optionPositionState(positionIds[0]);
    expect(state).to.be.equal(2); // ACTIVE
  });

  it("Should be able to close a position", async() => {
    const { vault, keeperHelper, deployer, markets } = testEnv;
    if(vault === undefined || keeperHelper === undefined || deployer === undefined || Object.keys(markets).length == 0) {
      throw new Error('testEnv not initialized');
    }
    const market = markets['BAYC'];
    const nft = market.nft;
    const optionToken = market.optionToken;
    const positionIds = await keeperHelper.getActiveOptions(nft);
    console.log(positionIds);
    let state = await optionToken.optionPositionState(positionIds[0]);
    expect(state).to.be.equal(2); // PENDING
    let strikeId = (await optionToken.optionPosition(positionIds[0])).strikeId;
    console.log(`strikeId: ${strikeId}`);
    let expiry = (await vault.strike(strikeId)).expiry;
    console.log(`${positionIds[0]} expired at ${expiry}`);
    await time.increaseTo(expiry);
    const expiredPositions = await keeperHelper.getExpiredOptions(nft);
    console.log(expiredPositions);
    await keeperHelper.batchCloseOptions(nft, expiredPositions);
  });
});