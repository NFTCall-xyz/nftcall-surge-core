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
import { processAllMarkets, resetRisk } from '../scripts/keeper';

task('keeper:fullUpdate', 'Full update')
    .setAction(async ({ }, hre) => {
        await hre.run('set-DRE');
        await processAllMarkets();
    });

task('keeper:resetRisk', 'Reset the risk of a market')
    .addParam('market', 'The market to reset')
    .setAction(async({market}, hre) => {
        await hre.run('set-DRE');
        await resetRisk(market);
    })