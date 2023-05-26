import { task } from 'hardhat/config';
import { 
    getAddress,
    getLPToken,
    getOracle,
    getPricer,
    getRiskCache,
    getReserve,
    getVault,
    deployVault,
    initializeMarket,
} from '../scripts/utils/contracts';

import {
    getMarkets
} from '../scripts/utils';

import { BigNumber } from 'ethers';
import { processMarket } from '../scripts/keeper';

task('keeper:updatePnl', 'Update the PNL')
    .addParam('timestamp', 'Timestamp')
    .setAction(async ({ timestamp }, hre) => {
        await hre.run('set-DRE');
        const vault = await getVault();
        if(!vault) throw new Error(`Vault not found`);
        await vault.updateUnrealizedPNL();
    });

task('keeper:closePositions', 'Close positions')
    .addParam('timestamp', 'Timestamp')
    .setAction(async ({ timestamp }, hre) => {
        await hre.run('set-DRE');
        const vault = await getVault();
        if(!vault) throw new Error(`Vault not found`);
        // await vault.closePositions();
    });

task('keeper:activatePositions', 'Activate positions')
    .addParam('timestamp', 'Timestamp')
    .setAction(async ({ timestamp }, hre) => {
        await hre.run('set-DRE');
        const vault = await getVault();
        if(!vault) throw new Error(`Vault not found`);
        // await vault.activatePositions();
    });

task('keeper:updateDelta', 'Update the delta')
    .addParam('timestamp', 'Timestamp')
    .setAction(async ({ timestamp }, hre) => {
        await hre.run('set-DRE');
        const vault = await getVault();
        if(!vault) throw new Error(`Vault not found`);
        // await vault.updateDelta();
    });

task('keeper:fullUpdate', 'Full update')
    .setAction(async ({ }, hre) => {
        await hre.run('set-DRE');
        const markets = await getMarkets();
        for(let market of markets){
            await processMarket(market);
        }
    });

task('keeper:test', 'test')
    .setAction(async({}, hre) => {
        await hre.run('set-DRE');
        const markets = await getMarkets();
    })