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
import { processAllMarkets } from '../scripts/keeper';

task('keeper:fullUpdate', 'Full update')
    .setAction(async ({ }, hre) => {
        await hre.run('set-DRE');
        await processAllMarkets();
    });

task('keeper:test', 'test')
    .setAction(async({}, hre) => {
        await hre.run('set-DRE');
        const markets = await getMarkets();
    })