import { makeSuite } from './make-suite';
import { expect } from "chai";
import { ethers } from "hardhat";

makeSuite("OptionPricer", function (testEnv) {

  it("should calculate the price of an option", async function () {
    const {pricer } = testEnv;
    if(pricer === undefined){
      throw new Error('testEnv not initialized');
    }
    // Set up test inputs
    const underlyingPrice = ethers.utils.parseEther("100");
    const strikePrice = ethers.utils.parseEther("110");
    const timeToExpiry = 30 * 24 * 60 * 60; // 30 days
    const volatility = ethers.utils.parseEther("0.3");
    const isPutOption = false;
    const amount = ethers.utils.parseEther("1");

    // Call the price function
    const prices = await pricer.optionPrices(
      underlyingPrice,
      strikePrice,
      volatility,
      timeToExpiry,
    );

    // Check that the price is correct
    expect(prices.call).to.be.gt(0);
    expect(prices.put).to.be.gt(0);
  });
});