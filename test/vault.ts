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
    const { vault, eth, lpToken, deployer, reserve } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || reserve === undefined){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("100");
    const fee = amount.mul(3).div(1000);
    await eth.mint(amount);
    await eth.approve(lpToken.address, amount);
    await vault.deposit(amount, deployer.address);
    await lpToken.approve(vault.address, amount);
    const releaseTime = await lpToken.releaseTime(deployer.address);
    await time.increaseTo(releaseTime.toNumber());
    await vault.claimLPToken(deployer.address);
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
    const amount = ethers.utils.parseEther("10000");
    await lpToken.approve(vault.address, amount);
    await expect(vault.withdraw(amount, deployer.address))
          .to.be.revertedWithCustomError(lpToken, "WithdrawMoreThanMax")
          .withArgs(lpToken.address, amount, amount.div(2));
  });

  it("Should be able to open a position", async () => {
    const { vault, keeperHelper, eth, lpToken, deployer, markets } = testEnv;
    if(vault === undefined || lpToken === undefined || eth === undefined || deployer === undefined || keeperHelper === undefined || Object.keys(markets).length == 0){
      throw new Error('testEnv not initialized');
    }
    const amount = ethers.utils.parseEther("100");
    await eth.mint(amount);
    await eth.approve(lpToken.address, amount);
    const market = markets['BAYC'];
    const nft = market.nft;
    const optionToken = market.optionToken;
    const expiry = await time.latest() + 28 * 3600 * 24;
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
    const estimatedPremium = openEvent.args['estimatedPremium'];
    expect(estimatedPremium).to.be.equal(BigNumber.from(778209).mul(150).add(50).div(100));
    await eth.approve(vault.address, estimatedPremium);
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
});