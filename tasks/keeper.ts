import { task } from 'hardhat/config';
import { BigNumber } from 'ethers';
import { processAllMarkets, resetRisk, cancelOptions } from '../scripts/keeper';

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

task('keeper:cancelOptions', 'cancel options')
    .addParam('market', 'The market to reset')
    .addVariadicPositionalParam('positionIds', 'The positionIds to cancel')
    .setAction(async({market, positionIds}, hre) => {
        await hre.run('set-DRE');
        await cancelOptions(market, positionIds.map((el: string) => BigNumber.from(el)));
    })