import {task} from 'hardhat/config';
import { 
    deployLPToken,
    deployBlackScholes,
    deployPricer,
    deployRiskCache,
    deployReserve,
    deployBackStopPool,
    deployKeeperHelper,
    initializeLPToken,
    getAddress,
    getContract,
    getLPToken,
    getOracle,
    getPricer,
    getRiskCache,
    getVault,
    waitTx,
} from '../scripts/utils/contracts';

import { ERC20 } from '../types';

import { bigNumber } from '../scripts/utils';
import { BigNumber } from 'ethers';

task('lpToken:deploy', 'Deploy LP Token')
    .addFlag('verify', 'Verify contract at Etherscan')
    .addParam('underlying', 'Underlying asset symbol')
    .addParam('underlyingName', 'Underlying asset name')
    .setAction(async ({ verify, underlying, underlyingName }, hre) => {
        await hre.run('set-DRE');
        const underlyingAddress = await getAddress(underlying);
        if(!underlyingAddress) throw new Error(`Asset ${underlying} not found`);
        const lpToken = await deployLPToken(underlyingAddress, `NFTCall ${underlyingName}`, `nc${underlyingName}`, verify);
    });

task('blackScholes:deploy', 'Deploy Black Scholes')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        await hre.run('set-DRE');
        const blackScholes = await deployBlackScholes(verify);
    });

task('pricer:deploy', 'Deploy Pricer')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        await hre.run('set-DRE');
        const pricer = await deployPricer(verify);
    });

task('riskCache:deploy', 'Deploy Risk Cache')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        await hre.run('set-DRE');
        const riskCache = await deployRiskCache(verify);
    });

task('reserve:deploy', 'Deploy Reserve')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        await hre.run('set-DRE');
        const reserve = await deployReserve(verify);
    });

task('backStopPool:deploy', 'Deploy BackStop Pool')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        await hre.run('set-DRE');
        const backStopPool = await deployBackStopPool(verify);
    });

task('lpToken:init', 'Initialize LP Token')
    .addParam('maximumSupply', 'Maximum supply of LP tokens')
    .setAction(async ({ maximumSupply }, hre) => {
        await hre.run('set-DRE');
        const lpToken = await getLPToken();
        if(!lpToken) throw new Error(`LP Token not found`);
        await initializeLPToken(bigNumber(parseInt(maximumSupply), 18));
    });

task('pricer:init', 'Initialize Pricer')
    .setAction(async ({ }, hre) => {
        await hre.run('set-DRE');
        const pricer = await getPricer();
        if(!pricer) throw new Error(`Pricer not found`);
        const riskCache = await getRiskCache();
        if(!riskCache) throw new Error(`Risk Cache not found`);
        const oracle = await getOracle();
        if(!oracle) throw new Error(`Oracle not found`);
        await waitTx(await pricer.initialize(riskCache.address, oracle.address));
    });

task('keeperHelper:deploy', 'Deploy KeeperHelper')
    .addFlag('verify', 'Verify contract at Etherscan')
    .setAction(async ({ verify }, hre) => {
        await hre.run('set-DRE');
        const vault = await getVault();
        if(!vault) throw new Error('Vault not found');
        const keeperHelper = await deployKeeperHelper(vault.address, verify);
        await vault.setKeeper(keeperHelper.address);
    })

