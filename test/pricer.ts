const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("OptionPricer", function () {
  let optionPricer;

  beforeEach(async function () {
    const OptionPricer = await ethers.getContractFactory("OptionPricer");
    optionPricer = await OptionPricer.deploy();
    await optionPricer.deployed();
  });

  it("should calculate the price of an option", async function () {
    // Set up test inputs
    const underlyingPrice = ethers.utils.parseEther("100");
    const strikePrice = ethers.utils.parseEther("110");
    const timeToExpiry = 30 * 24 * 60 * 60; // 30 days
    const volatility = ethers.utils.parseEther("0.3");
    const isPutOption = false;
    const amount = ethers.utils.parseEther("1");

    // Call the price function
    const price = await optionPricer.price(
      underlyingPrice,
      strikePrice,
      timeToExpiry,
      volatility,
      isPutOption,
      amount
    );

    // Check that the price is correct
    expect(price).to.be.gt(0);
  });
});