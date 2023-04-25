import { expect } from 'chai';
import { ethers } from 'ethers';
import { time } from '@nomicfoundation/hardhat-network-helpers'
import { makeSuite } from './make-suite';
import { bigNumber } from '../scripts/utils';
import { waitTx } from '../scripts/utils/contracts';
import { OptionTokenInterface } from '../types/contracts/tokens/OptionToken';

makeSuite('Vault', (testEnv) => {
  before(async () => {
  });

  it("Should be able to deposit", async () => {
    const { vault, dai, lpToken, deployer } = testEnv;
    if(vault === undefined || lpToken === undefined || dai === undefined || deployer === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("10000");
    await dai.mint(amount);
    await dai.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    const balance = await lpToken.lockedBalanceOf(deployer.address);
    expect(balance).to.be.equal(amount);
  });

  it("Should not be able to withdraw", async() => {
    const { vault, deployer, lpToken} = testEnv;
    if(vault == undefined || lpToken == undefined || deployer == undefined) {
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther('100');
    await expect(vault.withdraw(amount, deployer.address))
          .to.be.revertedWithCustomError(lpToken, "WithdrawMoreThanMax")
          .withArgs(lpToken.address, amount, 0);
  })

  it("Should not be able to claim", async() => {
    const { deployer, lpToken} = testEnv;
    if(lpToken == undefined || deployer == undefined) {
      throw new Error('testEnv not initialized');
    }
    const releaseTime = await lpToken.releaseTime(deployer.address);
    const blockTimestamp = await time.latest() + 1;
    await time.setNextBlockTimestamp(blockTimestamp);
    await expect(lpToken.claim(deployer.address))
          .to.be.revertedWithCustomError(lpToken, "ClaimBeforeReleaseTime")
          .withArgs(lpToken.address, deployer.address, releaseTime, blockTimestamp);
  })

  it("Should be able to withdraw", async () => {
    const { vault, dai, lpToken, deployer, reserve } = testEnv;
    if(vault === undefined || lpToken === undefined || dai === undefined || deployer === undefined || reserve === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("100");
    const fee = amount.mul(3).div(1000);
    await dai.mint(amount);
    await dai.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    await lpToken.approve(vault.address, amount);
    const releaseTime = await lpToken.releaseTime(deployer.address);
    await time.increaseTo(releaseTime.toNumber());
    await lpToken.claim(deployer.address);
    await vault.withdraw(amount, deployer.address);
    const balance = await dai.balanceOf(deployer.address);
    expect(balance).to.be.equal(amount.sub(fee));
    const reserveBalance = await dai.balanceOf(reserve.address);
    expect(reserveBalance).to.be.equal(fee);
  });

  it("Should not be able to withdraw all the remaining assets", async () => {
    const { vault, dai, lpToken, deployer } = testEnv;
    if(vault === undefined || lpToken === undefined || dai === undefined || deployer === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("10000");
    await lpToken.approve(vault.address, amount);
    await expect(vault.withdraw(amount, deployer.address))
          .to.be.revertedWithCustomError(lpToken, "WithdrawMoreThanMax")
          .withArgs(lpToken.address, amount, amount.div(2));
  });

  it("Should be able to open a position", async () => {
    const { vault, dai, lpToken, deployer, markets } = testEnv;
    if(vault === undefined || lpToken === undefined || dai === undefined || deployer === undefined || Object.keys(markets).length == 0){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("100");
    await dai.mint(amount);
    await dai.approve(lpToken.address, amount);
    const market = markets['BAYC'];
    const nft = market.nft;
    const optionToken = market.optionToken;
    const expiry = await time.latest() + 4 * 3600 * 24;
    const openTxRec = await waitTx(
      await vault.openPosition(
        nft, 
        deployer.address, 
        0, 
        bigNumber(12, 19), 
        expiry, 
        bigNumber(1, 18)));
    const events = openTxRec.events;
    expect(events).is.not.undefined;
    const openEvent = events[events.length - 1];
    expect(openEvent.args['estimatedPremium']).to.be.greaterThan(0);
  });
});