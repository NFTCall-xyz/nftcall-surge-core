import { task } from 'hardhat/config';
import { 
    getAddress,
    getLPToken,
    getOracle,
    getPricer,
    getRiskCache,
    getReserve,
    getBackStopPool,
    getVault,
    deployVault,
    initializeMarket,
} from '../scripts/utils/contracts';

import { BigNumber } from 'ethers';


task('vault:deploy', 'Deploy Vault')
    .addFlag('verify', 'Verify contract at Etherscan')
    .addParam('asset', 'Asset Symbol')
    .setAction(async ({ verify, asset }, hre) => {
        await hre.run('set-DRE');
        const underlyingAddress = await getAddress(asset);
        if(!underlyingAddress) throw new Error(`Asset ${asset} not found`);
        const lpToken = await getLPToken();
        if(!lpToken) throw new Error(`LP Token not found`);
        const oracle = await getOracle();
        if(!oracle) throw new Error(`Oracle not found`);
        const pricer = await getPricer();
        if(!pricer) throw new Error(`Pricer not found`);
        const riskCache = await getRiskCache();
        if(!riskCache) throw new Error(`Risk Cache not found`);
        const reserve = await getReserve();
        if(!reserve) throw new Error(`Reserve not found`);
        const backStopPool = await getBackStopPool();
        if(!backStopPool) throw new Error(`BackStopPool not found`);
        const vault = await deployVault(
            underlyingAddress, 
            lpToken.address, 
            oracle.address, 
            pricer.address, 
            riskCache.address, 
            reserve.address, 
            backStopPool.address, 
            verify);
    });

task('vault:initMarket', 'Initialize market')
    .addParam('market', 'Market Symbol')
    .addParam('weight', 'Weight')
    .setAction(async ({ market, weight }, hre) => {
        await hre.run('set-DRE');
        const vault = await getVault();
        if(!vault) throw new Error(`Vault not found`);
        await initializeMarket(market, BigNumber.from(parseInt(weight)));
    });